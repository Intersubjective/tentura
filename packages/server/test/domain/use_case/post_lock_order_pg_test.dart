@Tags(['pg'])
library;

import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_dispatch_repository.dart';
import 'package:tentura_server/data/repository/beacon_access_repository.dart';
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/forward_attribution_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/post_lock_repository.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_contact_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/entity/forward_delivery_result.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';
import 'package:tentura_server/domain/port/beacon_room_notification_context_port.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/port/person_visibility_repository_port.dart';
import 'package:tentura_server/domain/port/post_lock_port.dart';
import 'package:tentura_server/domain/use_case/attention_intent_case.dart';
import 'package:tentura_server/domain/use_case/forward_case.dart';
import 'package:tentura_server/domain/use_case/transactional_attention_case.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/fake_beacon_access_guard.dart';
import '../../support/fake_user_block_repository.dart';

/// Post mutations take one lock sequence (hierarchy scope → per-request
/// advisory lock → beacon row) and re-check every mutable fact after it, so a
/// block committed while a forward is in flight is honoured and the two paths
/// can never deadlock. See `docs/plans/post-and-constellation-composer-plan.md`
/// §4.10.
const _author = 'Upostlockauth1';
const _recipient = 'Upostlockrcpt1';
const _bystander = 'Upostlockbyst1';
const _post = 'Bpostlockpost1';

const _statusOpen = 0;
const _deadlockDetected = '40P01';
const _rounds = 20;
const _roundBudget = Duration(seconds: 10);

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_POST_LOCK_ORDER_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_post_lock',
  );

  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('Post lock order', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    // Drift keeps a single pooled connection per TenturaDb, so the two sides
    // of every race use separate databases to really run concurrently.
    late TenturaDb forwardDb;
    late TenturaDb blockDb;
    late _Stack forwardStack;
    late _Stack blockStack;

    setUpAll(() async {
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      forwardDb = openDisposablePgDatabase(target);
      blockDb = openDisposablePgDatabase(target);
      forwardStack = _buildStack(forwardDb, target.databaseEnv);
      blockStack = _buildStack(blockDb, target.databaseEnv);
    });

    setUp(() async {
      await _resetFixture(writer);
    });

    tearDownAll(() async {
      await blockDb.close();
      await tearDownDisposablePgWriter(session: session, drift: forwardDb);
    });

    group('lock helper', () {
      test(
        'waits for the global hierarchy lock held by another transaction',
        () async {
          final holder = await _openConnection(target);
          addTearDown(holder.close);
          await holder.execute('BEGIN');
          await holder.execute(
            "SELECT pg_advisory_xact_lock(hashtextextended('tentura.beacon_hierarchy.v1', 0))",
          );

          final acquired = _track(
            forwardStack.uow.run(
              actorUserId: _author,
              action: () => forwardStack.postLock.lockForPostMutation(_post),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 600));
          expect(acquired.isDone, isFalse, reason: 'lock is still held');

          await holder.execute('COMMIT');
          await acquired.future.timeout(_roundBudget);
        },
      );

      test('waits for the per-request advisory lock', () async {
        final holder = await _openConnection(target);
        addTearDown(holder.close);
        await holder.execute('BEGIN');
        await holder.execute(
          "SELECT pg_advisory_xact_lock(hashtextextended('$_post', 4242))",
        );

        final acquired = _track(
          forwardStack.uow.run(
            actorUserId: _author,
            action: () => forwardStack.postLock.lockForPostMutation(_post),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(acquired.isDone, isFalse, reason: 'lock is still held');

        await holder.execute('COMMIT');
        await acquired.future.timeout(_roundBudget);
      });

      test('waits for a row lock on the beacon', () async {
        final holder = await _openConnection(target);
        addTearDown(holder.close);
        await holder.execute('BEGIN');
        await holder.execute(
          "SELECT 1 FROM public.beacon WHERE id = '$_post' FOR UPDATE",
        );

        final acquired = _track(
          forwardStack.uow.run(
            actorUserId: _author,
            action: () => forwardStack.postLock.lockForPostMutation(_post),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 600));
        expect(acquired.isDone, isFalse, reason: 'row lock is still held');

        await holder.execute('COMMIT');
        await acquired.future.timeout(_roundBudget);
      });

      test('returns promptly when nothing else holds a lock', () async {
        await forwardStack.uow
            .run<void>(
              actorUserId: _author,
              action: () => forwardStack.postLock.lockForPostMutation(_post),
            )
            .timeout(_roundBudget);
      });
    });

    group('forward of a Post', () {
      test(
        'a block committed after the beacon read but before the lock stops '
        'the forward from admitting the blocked recipient',
        () async {
          final reachedBarrier = Completer<void>();
          final resume = Completer<void>();
          forwardStack.forwardCase.beforeLockForTest = () async {
            reachedBarrier.complete();
            await resume.future;
          };
          addTearDown(() => forwardStack.forwardCase.beforeLockForTest = null);

          final forward = _settle(
            forwardStack.forwardCase.forward(
              senderId: _author,
              beaconId: _post,
              recipientIds: const [_recipient],
            ),
          );
          await reachedBarrier.future.timeout(_roundBudget);

          await blockStack.blockCase.block(
            blockerId: _recipient,
            blockedId: _author,
            cascadeMode: 0,
          );
          resume.complete();
          final outcome = await forward.timeout(_roundBudget);

          // The repo has no dedicated block exception; a block surfaces to the
          // sender as the same authorization failure the other recipient
          // checks raise.
          expect(
            outcome.error,
            isA<UnauthorizedException>().having(
              (e) => e.code.codeNumber,
              'code',
              const AuthExceptionCodes(
                AuthExceptionCode.authUnauthorizedException,
              ).codeNumber,
            ),
            reason:
                'a forward that resumed after the block must be rejected, not '
                'silently drop the recipient (result: '
                '${outcome.result?.deliveredRecipientIds})',
          );
          expect(_isDeadlock(outcome.error), isFalse);
          expect(
            await _edgeCount(writer, _post, _recipient, liveOnly: false),
            0,
            reason: 'no edge row of any state may be created for the recipient',
          );
          expect(await _isAdmitted(writer, _post, _recipient), isFalse);
        },
      );

      test(
        'a forward racing a block never deadlocks and never leaves the '
        'blocked recipient admitted',
        () async {
          for (var round = 0; round < _rounds; round++) {
            await _resetFixture(writer);

            final forward = _settle(
              forwardStack.forwardCase.forward(
                senderId: _author,
                beaconId: _post,
                recipientIds: const [_recipient],
              ),
            );
            final block = _settle(
              blockStack.blockCase.block(
                blockerId: _recipient,
                blockedId: _author,
                cascadeMode: 0,
              ),
            );
            final outcomes =
                await Future.wait([
                  forward,
                  block,
                ]).timeout(
                  _roundBudget,
                  onTimeout: () => fail('round $round did not finish in 10 s'),
                );

            for (final outcome in outcomes) {
              expect(
                _isDeadlock(outcome.error),
                isFalse,
                reason: 'round $round: deadlock_detected: ${outcome.error}',
              );
            }

            final forwardOutcome = outcomes[0];
            if (forwardOutcome.error != null) {
              expect(
                forwardOutcome.error,
                isA<ExceptionBase>(),
                reason:
                    'round $round: a forward that loses to the block fails '
                    'with a domain exception',
              );
              expect(
                await _edgeCount(writer, _post, _recipient, liveOnly: false),
                0,
                reason: 'round $round: a failed forward leaves no edge',
              );
            } else {
              final delivered =
                  forwardOutcome.result?.deliveredRecipientIds ??
                  const <String>[];
              expect(
                await _edgeCount(writer, _post, _recipient, liveOnly: false),
                delivered.contains(_recipient) ? 1 : 0,
                reason:
                    'round $round: a successful forward names the recipient '
                    'exactly when an edge was created for it',
              );
              expect(
                await _liveEdgeCount(writer, _post, _recipient),
                0,
                reason: 'round $round: the edge must be cancelled by the block',
              );
            }
            expect(
              await _isAdmitted(writer, _post, _recipient),
              isFalse,
              reason: 'round $round: blocked recipient must not stay admitted',
            );
          }
        },
        timeout: const Timeout(Duration(minutes: 5)),
      );

      test(
        'an unrelated recipient is still admitted by the Post forward',
        () async {
          final result = await forwardStack.forwardCase.forward(
            senderId: _author,
            beaconId: _post,
            recipientIds: const [_bystander],
          );

          expect(result.deliveredRecipientIds, [_bystander]);
          expect(await _isAdmitted(writer, _post, _bystander), isTrue);
        },
      );
    });
  });
}

_Tracked _track(Future<void> future) => _Tracked(future);

final class _Tracked {
  _Tracked(Future<void> future) {
    this.future = future.whenComplete(() => isDone = true);
  }

  late final Future<void> future;
  bool isDone = false;
}

typedef _Outcome = ({Object? error, ForwardDeliveryResult? result});

Future<_Outcome> _settle(Future<Object?> action) async {
  try {
    final value = await action;
    return (
      error: null,
      result: value is ForwardDeliveryResult ? value : null,
    );
  } on Object catch (error) {
    return (error: error, result: null);
  }
}

Future<Connection> _openConnection(DisposablePgTarget target) =>
    Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );

Future<void> _resetFixture(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.user_block,
  public.user_block_intent,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  for (final id in [_author, _recipient, _bystander]) {
    await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('$id', '$id', 'pk-$id')
''');
  }
  await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, kind, is_discoverable,
   published_at)
VALUES ('$_post', '$_author', '', '', $_statusOpen, 1, false, now())
''');
}

/// SQLSTATE `40P01`, however the driver or drift wrapped it.
bool _isDeadlock(Object? error) {
  if (error == null) return false;
  if (error is ServerException && error.code == _deadlockDetected) return true;
  final text = '$error'.toLowerCase();
  return text.contains(_deadlockDetected.toLowerCase()) ||
      text.contains('deadlock');
}

Future<int> _liveEdgeCount(
  Connection writer,
  String beaconId,
  String recipientId,
) => _edgeCount(writer, beaconId, recipientId, liveOnly: true);

Future<int> _edgeCount(
  Connection writer,
  String beaconId,
  String recipientId, {
  required bool liveOnly,
}) async =>
    (await writer.execute('''
SELECT count(*) FROM public.beacon_forward_edge
WHERE beacon_id = '$beaconId' AND recipient_id = '$recipientId'
  ${liveOnly ? 'AND cancelled_at IS NULL' : ''}
''')).single.single!
        as int;

Future<bool> _isAdmitted(
  Connection writer,
  String beaconId,
  String userId,
) async => (await writer.execute('''
SELECT 1 FROM public.beacon_participant
WHERE beacon_id = '$beaconId' AND user_id = '$userId'
  AND room_access = ${RoomAccessBits.admitted}
''')).isNotEmpty;

final class _Stack {
  const _Stack({
    required this.forwardCase,
    required this.blockCase,
    required this.postLock,
    required this.uow,
  });

  final ForwardCase forwardCase;
  final UserBlockCase blockCase;
  final PostLockPort postLock;
  final MutatingUnitOfWork uow;
}

_Stack _buildStack(TenturaDb db, Env env) {
  final logger = Logger('PostLockOrderPgTest');
  final uow = MutatingUnitOfWork(db);
  final postLock = PostLockRepository(db);
  final hierarchy = BeaconHierarchyRepository(db);
  final beacons = BeaconRepository(db);
  final helpOffers = HelpOfferRepository(db);
  final inbox = InboxRepository(db);
  final capability = CapabilityEvidenceRepository(db);
  final forwardEdges = ForwardEdgeRepository(db);
  final witnessWindow = WitnessWindowRepository(db);
  final blocks = UserBlockRepository(
    env,
    db,
    witnessWindow: witnessWindow,
  );
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
  final intents = AttentionIntentCase(
    _NoopNotificationContext(),
    users,
    FakeBeaconAccessGuard(),
    FakeUserBlockRepository(),
  );

  return _Stack(
    uow: uow,
    postLock: postLock,
    forwardCase: ForwardCase(
      forwardEdges,
      ForwardAttributionRepository(db),
      helpOffers,
      inbox,
      capability,
      beacons,
      blocks,
      _AllVisiblePeers(),
      BeaconAccessRepository(db),
      postLock: postLock,
      attentionIntents: intents,
      attention: attention,
      env: env,
      logger: logger,
    ),
    blockCase: UserBlockCase(
      uow,
      blocks,
      helpOffers,
      forwardEdges,
      UserContactRepository(db),
      users,
      beacons,
      CommitmentRepository(db),
      inbox,
      capability,
      hierarchy,
      trustLedger: TrustLedgerRepository(db),
      witnessWindow: witnessWindow,
      env: env,
      logger: logger,
    ),
  );
}

final class _NoopInviteGenealogyRepository extends Fake
    implements InviteGenealogyRepositoryPort {}

final class _NoopNotificationContext extends Fake
    implements BeaconRoomNotificationContextPort {}

final class _AllVisiblePeers extends Fake
    implements PersonVisibilityRepositoryPort {
  @override
  Future<Set<String>> personVisiblePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
    required String context,
  }) async => peerIds.toSet();
}
