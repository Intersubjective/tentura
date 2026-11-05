@Tags(['pg'])
library;

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_notification_context_repository.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/entity/forward_delivery_result.dart';
import 'package:tentura_server/domain/invite_genealogy/invite_genealogy_node_key.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

/// A cascade batch that materializes two inherited blocks in one transaction
/// races a concurrent Post forward sent by the *second* blocked candidate.
/// The batch takes each candidate's per-user block barrier exclusively one at
/// a time (m0294 row trigger) and bumps `visibility_trust_generation` after
/// every block INSERT (m0235 statement trigger); the forward takes the sender's
/// barrier shared (m0294 comment) and then projects trust through
/// `contact_engage` (m0206), which writes `user_trust_edge` and so bumps the
/// same generation counter. With the batch holding the generation row after the
/// first INSERT and waiting for the second candidate's exclusive barrier while
/// the forward holds that candidate's shared barrier and waits for the
/// generation row, the two lock in a cycle Postgres resolves as SQLSTATE
/// `40P01`. The batch is paused after its first INSERT (so it provably holds
/// the generation row) before the forward starts, so the overlap is forced.
/// See the #941 lock order.
const _blockerId = 'Ucaspdblocker1';
const _originId = 'Ucaspdorigin01';
const _candidateAId = 'UcaspdcandA001';
const _candidateBId = 'UcaspdcandB001';
const _authorId = 'Ucaspdauthor1';
const _priorSenderId = 'Ucaspdpsnder1';
const _recipientId = 'Ucaspdrcpt001';
const _postId = 'Bcaspdpost0001';
const _priorEdgeId = 'Fcaspdprior01';

const _pauseKey =
    "hashtextextended('tentura.test.cascade_post_forward_pause', 0)";
const _deadlockDetected = '40P01';
const _budget = Duration(seconds: 15);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BLOCK_CASCADE_POST_FORWARD_DEADLOCK_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_bcpfd',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Cascade batch racing a Post forward of the second candidate', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late Env env;
    late TenturaDb cascadeDb;
    late TenturaDb forwardDb;
    late UserBlockRepository cascadeRepo;
    late ForwardCase forwardCase;
    late int cascadePid;
    late int forwardPid;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      env = Env(
        environment: Environment.test,
        pgHost: target.databaseEnv.pgHost,
        pgPort: target.databaseEnv.pgPort,
        pgDatabase: target.databaseName,
        pgUsername: target.databaseEnv.pgUsername,
        pgPassword: target.databaseEnv.pgPassword,
        genealogyNodeKeySecret: 'test-genealogy-secret',
        blockCascadeBatchSize: 500,
      );
      cascadeDb = openDisposablePgDatabase(target);
      forwardDb = openDisposablePgDatabase(target);
      cascadeRepo = UserBlockRepository(env, cascadeDb);
      forwardCase = _buildForwardStack(forwardDb, env);

      // AFTER INSERT STATEMENT trigger that runs after the m0235 generation
      // bump (alphabetical order: visibility... < zz_test...), so the batch is
      // frozen with the generation row already locked. The test holds the
      // matching session advisory lock to pause the batch after each
      // statement-level INSERT.
      await writer.execute('''\nCREATE FUNCTION public.zz_test_cascade_post_forward_pause() RETURNS trigger\nLANGUAGE plpgsql\nAS \$\$\nBEGIN\n  PERFORM pg_advisory_xact_lock_shared($_pauseKey);\n  RETURN NULL;\nEND;\n\$\$\n''');
      await writer.execute(
        'CREATE TRIGGER zz_test_cascade_post_forward_pause_trg '
        'AFTER INSERT ON public.user_block '
        'FOR EACH STATEMENT EXECUTE FUNCTION '
        'public.zz_test_cascade_post_forward_pause()',
      );
    });

    setUp(() async {
      await _resetFixture(writer, env);
      await _seedIntent(writer);
      cascadePid = await _backendPid(cascadeDb);
      forwardPid = await _backendPid(forwardDb);
    });

    tearDownAll(() async {
      await forwardDb.close();
      await tearDownDisposablePgWriter(session: session, drift: cascadeDb);
    });

    test(
      'a two-candidate cascade batch and a concurrent Post forward sent by '
      'the second candidate never deadlock (SQLSTATE 40P01) and both commit',
      () async {
        final pauser = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        addTearDown(pauser.close);
        await pauser.execute('SELECT pg_advisory_lock($_pauseKey)');

        final cascade = _settle(
          cascadeRepo.materializeCascadeBatch(
            blockerId: _blockerId,
            blockedId: _originId,
            limit: 2,
          ),
        );
        await _waitForLockWait(
          writer,
          cascadePid,
          label: 'the cascade batch paused after its first INSERT',
        );
        // The batch is paused by the AFTER INSERT STATEMENT trigger that runs
        // after the m0235 generation bump (alphabetical order). We do NOT pin
        // the m0294 advisory key format here: the pause is observable purely
        // as the batch waiting on the test pause lock, which is independent of
        // how the fix takes its barriers. A fix that uses a different barrier
        // key scheme or a batch-level lock still passes this precondition.
        expect(
          await _isWaitingOn(writer, cascadePid, _pauseKey),
          isTrue,
          reason: 'the batch is paused on the test pause lock, not another '
              'lock that would invalidate the race',
        );
        // Prove the batch has already bumped `visibility_trust_generation`
        // before it pauses: the m0235 AFTER INSERT STATEMENT trigger fires
        // before the pause trigger (alphabetical order: visibility... <
        // zz_test...), so the batch holds the single generation row until
        // commit. That row is exactly what the forward waits on under the
        // baseline cycle. The check is shape-independent — it does not pin the
        // per-row insert count — so a correct fix that bumps the generation
        // once per batch (e.g. one multi-row INSERT with a single
        // statement-level bump) still holds this row when paused and passes.
        expect(
          await _holdsVisibilityGenerationRow(writer, cascadePid),
          isTrue,
          reason: 'the batch holds the visibility_trust_generation row when '
              'paused, which is the lock the forward waits on under the '
              'baseline cycle; this is independent of the insert shape so a '
              'batch-level generation bump still passes',
        );

        final forward = _settle(
          forwardCase.forward(
            senderId: _candidateBId,
            beaconId: _postId,
            recipientIds: const [_recipientId],
          ),
        );
        // The overlap is forced: assert the forward is actually blocked on a
        // lock (not already finished). A fix that makes the forward
        // non-blocking would pass the deadlock check below without exercising
        // the race; this assertion makes such a fix fail loudly. On the
        // baseline the forward blocks on the generation row held by the batch;
        // after a correct fix (barriers taken in order, or generation bumped
        // once per batch) the forward still blocks on the second candidate's
        // barrier held by the batch, so this assertion stays green.
        await _waitForBlocked(
          writer,
          forwardPid,
          blockedByPid: cascadePid,
          label: 'the Post forward sent by the second candidate',
        );

        await pauser.execute('SELECT pg_advisory_unlock($_pauseKey)');

        final outcomes = await Future.wait([cascade, forward]).timeout(
          _budget,
          onTimeout: () => fail('cascade and forward did not settle in 15 s'),
        );

        expect(
          outcomes[0].error,
          isNull,
          reason: 'the cascade side must commit with no error (got '
              '${outcomes[0].error}); a non-deadlock failure here is a real '
              'regression, not just a missing block B',
        );
        expect(
          _isDeadlock(outcomes[0].error),
          isFalse,
          reason: 'the cascade side must not fail with $_deadlockDetected '
              'deadlock_detected: ${outcomes[0].error}',
        );
        expect(
          _isDeadlock(outcomes[1].error),
          isFalse,
          reason: 'the forward side must not fail with $_deadlockDetected '
              'deadlock_detected: ${outcomes[1].error}',
        );
        expect(await _blockExists(writer, _blockerId, _candidateAId), isTrue);
        expect(
          await _blockExists(writer, _blockerId, _candidateBId),
          isTrue,
          reason: 'the second candidate is materialized with no deadlock',
        );
        expect(
          outcomes[1].error,
          isNull,
          reason: 'the forward completes once the cycle is broken: '
              '${outcomes[1].error}',
        );
        expect(
          outcomes[1].result?.deliveredRecipientIds,
          [_recipientId],
          reason: 'the forward did real work, not a no-op: the stubbed '
              '_AllVisiblePeers visibility port admits every peer (including '
              '$_recipientId), so a forward that commits with no error must '
              'deliver to the recipient it was sent to — this confirms the '
              'forward path ran end to end once the cycle was broken, rather '
              'than the test passing because the forward silently dropped '
              'the recipient',
        );
      },
      timeout: const Timeout(Duration(minutes: 3)),
    );
  });
}

typedef _Outcome = ({
  Object? error,
  ForwardDeliveryResult? result,
  Object? value,
});

Future<_Outcome> _settle(Future<Object?> action) async {
  try {
    final value = await action;
    return (
      error: null,
      result: value is ForwardDeliveryResult ? value : null,
      value: value,
    );
  } on Object catch (error) {
    return (error: error, result: null, value: null);
  }
}

/// SQLSTATE `40P01` only — the driver/drift wrapper carries the code on
/// `ServerException.code`. Do not broaden this to any error whose text
/// mentions "deadlock": that would misclassify an unrelated message as the
/// cycle and weaken the diagnosis the test prints.
bool _isDeadlock(Object? error) {
  if (error is ServerException && error.code == _deadlockDetected) return true;
  return false;
}

Future<int> _backendPid(TenturaDb db) async {
  final row = await db.customSelect('SELECT pg_backend_pid() AS pid').getSingle();
  return row.read<int>('pid');
}

/// Whether backend [pid] holds a granted lock on the
/// `visibility_trust_generation` table — i.e. the m0235 AFTER INSERT STATEMENT
/// trigger has already bumped the generation row inside [pid]'s transaction.
/// The bump is an `UPDATE` on the single row (id = true), which takes a
/// `RowExclusiveLock` on the table held until commit. This is shape
/// independent: a single multi-row INSERT with one statement-level bump, or
/// sequential per-row INSERTs, both hold this lock once the statement trigger
/// has fired, so a correct "bump the generation once per batch" fix passes.
Future<bool> _holdsVisibilityGenerationRow(Connection writer, int pid) async {
  final rows = await writer.execute(
    '''
SELECT 1 FROM pg_locks l
WHERE l.pid = $pid AND l.granted = true
AND l.relation = (
  SELECT oid FROM pg_class WHERE relname = 'visibility_trust_generation')
''',
  );
  return rows.isNotEmpty;
}

Future<bool> _blockExists(
  Connection writer,
  String blocker,
  String blocked,
) async {
  final rows = await writer.execute(
    'SELECT 1 FROM public.user_block '
    "WHERE blocker_id = '$blocker' AND blocked_id = '$blocked' "
    "AND origin_id = '$_originId' LIMIT 1",
  );
  return rows.isNotEmpty;
}

String _advisoryLockFilter(int pid, String keyExpr) =>
    "l.locktype = 'advisory' AND l.objsubid = 1 "
    'AND ((l.classid::bigint << 32) | l.objid::bigint) = $keyExpr '
    'AND l.pid = $pid AND l.database = '
    '(SELECT oid FROM pg_database WHERE datname = current_database())';

/// Whether backend [pid] is waiting (not granted) on the advisory lock
/// [keyExpr].
Future<bool> _isWaitingOn(
  Connection writer,
  int pid,
  String keyExpr,
) async {
  final rows = await writer.execute(
    'SELECT 1 FROM pg_locks l '
    'WHERE NOT l.granted AND ${_advisoryLockFilter(pid, keyExpr)}',
  );
  return rows.isNotEmpty;
}

Future<void> _waitForLockWait(
  Connection writer,
  int pid, {
  required String label,
}) async {
  final deadline = DateTime.now().add(_budget);
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      'SELECT 1 FROM pg_stat_activity '
      "WHERE pid = $pid AND wait_event_type = 'Lock'",
    );
    if (rows.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('backend $pid never blocked on $label');
}

/// Waits until backend [pid] is blocked on a lock held by [blockedByPid]'s
/// transaction, and fails if the action finishes first. Checking only
/// `wait_event_type = 'Lock'` would let an unrelated lock (e.g. the Post lock,
/// or an advisory lock from a different transaction) satisfy the wait while
/// the forward never actually overlaps the batch; requiring the blocker to be
/// the batch's backend keeps the overlap real. This proves the overlap is
/// forced: a forward that completes without ever waiting on the batch did not
/// race it and cannot testify about the cycle.
Future<void> _waitForBlocked(
  Connection writer,
  int pid, {
  required int blockedByPid,
  required String label,
}) async {
  final deadline = DateTime.now().add(_budget);
  while (DateTime.now().isBefore(deadline)) {
    final rows = await writer.execute(
      '''
SELECT 1 FROM pg_stat_activity a
WHERE a.pid = $pid AND a.wait_event_type = 'Lock'
AND $blockedByPid = ANY(pg_blocking_pids(a.pid))
''',
    );
    if (rows.isNotEmpty) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('backend $pid never blocked on $label (held by $blockedByPid) within '
      '15 s; the forward finished without racing the batch, so the overlap '
      'was not forced');
}

Future<void> _seedIntent(Connection writer) async {
  await writer.execute('SELECT pg_advisory_lock($_pauseKey)');
  await writer.execute('''
INSERT INTO public.user_block_intent (
  blocker_id, blocked_id, cascade_mode, cascade_status,
  cascade_snapshot_at, created_at, updated_at
) VALUES (
  '$_blockerId', '$_originId', 1, 0, now(), now(), now()
)
ON CONFLICT (blocker_id, blocked_id) DO UPDATE SET
  cascade_mode = EXCLUDED.cascade_mode,
  cascade_status = 0,
  cascade_snapshot_at = now(),
  updated_at = now()
''');
  await writer.execute('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$_blockerId', '$_originId', '$_originId')
ON CONFLICT DO NOTHING
''');
  await writer.execute('SELECT pg_advisory_unlock($_pauseKey)');
}

Future<void> _resetFixture(Connection writer, Env env) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence_recipient,
  public.attention_occurrence,
  public.beacon_help_offer,
  public.invitation,
  public.user_block,
  public.user_block_intent,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.inbox_item,
  public.user_trust_edge,
  public.trust_evidence,
  public.trust_publish_queue,
  public.beacon,
  public."user"
CASCADE
''');
  final tRoot = DateTime.utc(2026);
  final tBranch = DateTime.utc(2026, 2);
  final tChild = DateTime.utc(2026, 3);
  for (final (id, at) in [
    (_blockerId, tRoot),
    (_originId, tBranch),
    (_candidateAId, tChild),
    (_candidateBId, tChild),
    (_authorId, tRoot),
    (_priorSenderId, tRoot),
    (_recipientId, tChild),
  ]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '${at.toIso8601String()}', '${at.toIso8601String()}')
''');
  }

  Future<void> edge(String ancestor, DateTime aAt, String child, DateTime cAt) =>
      writer.execute('''
INSERT INTO public.invite_genealogy (
  descendant_node_key, ancestor_node_key, descendant_user_id,
  ancestor_user_id, ancestor_user_created_at, descendant_user_created_at,
  created_at
) VALUES (
  '${InviteGenealogyNodeKey.derive(userId: child, env: env)}',
  '${InviteGenealogyNodeKey.derive(userId: ancestor, env: env)}',
  '$child', '$ancestor',
  '${aAt.toIso8601String()}', '${cAt.toIso8601String()}', now()
)
''');
  // candidateA sorts before candidateB, so the batch inserts A first and B
  // second: the forward is sent by the *second* candidate.
  await edge(_originId, tBranch, _candidateAId, tChild);
  await edge(_originId, tBranch, _candidateBId, tChild);

  // An open Post (kind = 1) with open forwarding (forward_policy = 1).
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at, forward_policy)
VALUES ('$_postId', '$_authorId', '', '', 0, 1, false, now(), 1)
''');
  // A prior inbound edge to the second candidate on this Post, with a contact
  // deadline set by the m0206 BEFORE INSERT trigger. When the second candidate
  // forwards the Post, contact_engage finds this edge and projects trust,
  // writing user_trust_edge and bumping visibility_trust_generation.
  await writer.execute('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('$_priorEdgeId', '$_postId', '$_priorSenderId', '$_candidateBId')
''');
  await writer.execute('''
INSERT INTO public.beacon_participant (beacon_id, user_id, room_access)
VALUES ('$_postId', '$_candidateBId', 3)
ON CONFLICT (beacon_id, user_id) DO UPDATE SET room_access = 3
''');
}

ForwardCase _buildForwardStack(TenturaDb db, Env env) {
  final logger = Logger('CascadePostForwardDeadlockTest');
  final uow = MutatingUnitOfWork(db);
  final postLock = PostLockRepository(db);
  final beacons = BeaconRepository(db);
  final helpOffers = HelpOfferRepository(db);
  final inbox = InboxRepository(db);
  final capability = CapabilityEvidenceRepository(db);
  final forwardEdges = ForwardEdgeRepository(db);
  final witnessWindow = WitnessWindowRepository(db);
  final blocks = UserBlockRepository(env, db, witnessWindow: witnessWindow);
  final users = UserRepository(
    env,
    db,
    _NoopInviteGenealogyRepository(),
    InviteSeedPromptRepositoryMock(),
  );
  final attention = TransactionalAttentionCase(
    uow,
    AttentionDispatchRepository(db, logger),
  );
  final roomRepository = BeaconRoomRepository(db);
  final commitments = CommitmentRepository(db);
  final access = BeaconAccessRepository(db);
  final intents = AttentionIntentCase(
    BeaconRoomNotificationContextRepository(
      roomRepository,
      db,
      helpOffers,
      commitments,
    ),
    users,
    FakeBeaconAccessGuard(),
    FakeUserBlockRepository(),
  );
  return ForwardCase(
    forwardEdges,
    ForwardAttributionRepository(db),
    helpOffers,
    inbox,
    capability,
    beacons,
    blocks,
    _AllVisiblePeers(),
    access,
    postLock: postLock,
    attentionIntents: intents,
    attention: attention,
    env: env,
    logger: logger,
  );
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _AllVisiblePeers extends Fake
    implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async =>
      peerIds.toSet();
}
