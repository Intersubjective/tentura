@Tags(['pg'])
library;

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_hierarchy_repository.dart';
import 'package:tentura_server/data/repository/beacon_repository.dart';
import 'package:tentura_server/data/repository/capability_evidence_repository.dart';
import 'package:tentura_server/data/repository/commitment_repository.dart';
import 'package:tentura_server/data/repository/forward_edge_repository.dart';
import 'package:tentura_server/data/repository/help_offer_repository.dart';
import 'package:tentura_server/data/repository/inbox_repository.dart';
import 'package:tentura_server/data/repository/mock/invite_seed_prompt_repository_mock.dart';
import 'package:tentura_server/data/repository/mutating_unit_of_work.dart';
import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_contact_repository.dart';
import 'package:tentura_server/data/repository/user_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/commitment/commitment_event_kind.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/domain/user_block/user_block_withdraw_reason.dart';

import 'package:mockito/mockito.dart' show Fake;

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

const _blocker = 'Ublkcl000001';
const _blocked = 'Ublkcl000002';

/// Authored by [_blocker]; [_blocked] holds an active offer on it.
const _blockersRequest = 'Bblkcl000001';

/// Authored by [_blocked]; [_blocker] holds an active offer on it.
const _blockedsRequest = 'Bblkcl000002';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_USER_BLOCK_OFFER_CLEANUP_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_user_block_offer_cleanup',
  );
  final pgSkip = await pgSkipReason(target);
  if (pgSkip != null) {
    test('Postgres unavailable', () {}, skip: pgSkip);
    return;
  }

  group('direct block cleanup of active offers', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late UserBlockCase blocks;
    late HelpOfferRepository helpOffers;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      final env = target.databaseEnv;
      final logger = Logger('UserBlockOfferCleanupPgTest');
      helpOffers = HelpOfferRepository(database);
      final witnessWindow = WitnessWindowRepository(database);
      blocks = UserBlockCase(
        MutatingUnitOfWork(database),
        UserBlockRepository(env, database, witnessWindow: witnessWindow),
        helpOffers,
        ForwardEdgeRepository(database),
        UserContactRepository(database),
        UserRepository(
          env,
          database,
          _UnusedGenealogy(),
          InviteSeedPromptRepositoryMock(),
        ),
        BeaconRepository(database),
        CommitmentRepository(database),
        InboxRepository(database),
        CapabilityEvidenceRepository(database),
        BeaconHierarchyRepository(database),
        trustLedger: TrustLedgerRepository(database),
        witnessWindow: witnessWindow,
        env: env,
        logger: logger,
      );
      await _installActorProbe(writer);
    });

    setUp(() async {
      await _seed(writer);
      await helpOffers.upsert(
        beaconId: _blockersRequest,
        userId: _blocked,
        message: 'I can help',
      );
      await helpOffers.upsert(
        beaconId: _blockedsRequest,
        userId: _blocker,
        message: 'I can help too',
      );
      await writer.execute('TRUNCATE TABLE public.test_actor_probe');
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test(
      'blocking a user with an active offer on the blocker request withdraws that offer',
      () async {
        await blocks.block(
          blockerId: _blocker,
          blockedId: _blocked,
          cascadeMode: 0,
        );

        final offer = await _offer(writer, _blockersRequest, _blocked);
        expect(offer.status, 1);
        expect(offer.withdrawReason, kBlockWithdrawReason);
        final events = await _commitmentEvents(
          writer,
          _blockersRequest,
          _blocked,
        );
        expect(events.map((e) => e.actor), [_blocked]);
        expect(events.map((e) => e.kind), [
          CommitmentEventKind.blockedCleanup.smallintValue,
        ]);
      },
    );

    test(
      'cleanup event for the blocked user is attributed to that user',
      () async {
        await blocks.block(
          blockerId: _blocker,
          blockedId: _blocked,
          cascadeMode: 0,
        );

        final events = await _commitmentEvents(
          writer,
          _blockersRequest,
          _blocked,
        );
        expect(events, [
          (
            actor: _blocked,
            kind: CommitmentEventKind.blockedCleanup.smallintValue,
            reason: kBlockWithdrawReason,
          ),
        ]);
      },
    );

    test('every cleanup write for both offer directions runs in one '
        'transaction acting as the blocker', () async {
      expect(
        (await _offer(writer, _blockersRequest, _blocked)).status,
        0,
        reason: 'precondition: the blocked user has an active offer',
      );
      expect(
        (await _offer(writer, _blockedsRequest, _blocker)).status,
        0,
        reason: 'precondition: the blocker has an active offer',
      );

      await blocks.block(
        blockerId: _blocker,
        blockedId: _blocked,
        cascadeMode: 0,
      );

      final probes = await _probes(writer);
      expect(
        probes.where((p) => p.beaconId == _blockersRequest),
        isNotEmpty,
        reason: 'the blocked user offer cleanup must have been written',
      );
      expect(
        probes.where((p) => p.beaconId == _blockedsRequest),
        isNotEmpty,
        reason: 'the blocker own offer cleanup must have been written',
      );
      expect(
        probes.map((p) => p.mutatingUser).toSet(),
        {_blocker},
        reason: 'the transaction actor is the blocker, not the offerer',
      );
      expect(
        probes.map((p) => p.txid).toSet(),
        hasLength(1),
        reason: 'all cleanup writes share a single transaction',
      );
      expect(
        probes.map((p) => p.txid).toSet().single,
        isNot(await _currentTxid(writer)),
        reason: 'sanity: the block transaction is not the probe reader',
      );
      expect(
        (await _commitmentEvents(
          writer,
          _blockersRequest,
          _blocked,
        )).map((e) => e.actor),
        [_blocked],
        reason: 'the event still attributes the offerer',
      );
      expect(
        (await _commitmentEvents(
          writer,
          _blockedsRequest,
          _blocker,
        )).map((e) => e.actor),
        [_blocker],
      );
    });

    test('blocker own offer on the blocked user request is withdrawn '
        'and attributed to the blocker', () async {
      await blocks.block(
        blockerId: _blocker,
        blockedId: _blocked,
        cascadeMode: 0,
      );

      final offer = await _offer(writer, _blockedsRequest, _blocker);
      expect(offer.status, 1);
      expect(offer.withdrawReason, kBlockWithdrawReason);
      final events = await _commitmentEvents(
        writer,
        _blockedsRequest,
        _blocker,
      );
      expect(events.map((e) => e.actor), [_blocker]);
      expect(events.map((e) => e.kind), [
        CommitmentEventKind.blockedCleanup.smallintValue,
      ]);
    });
  });
}

typedef _Probe = ({
  String table,
  String beaconId,
  String? mutatingUser,
  int txid,
});

/// Records the `tentura.mutating_user_id` in force for each write the cleanup
/// makes, so the transaction actor can be read back from the database.
Future<void> _installActorProbe(Connection writer) async {
  await writer.execute('''
CREATE TABLE IF NOT EXISTS public.test_actor_probe (
  seq bigserial PRIMARY KEY,
  tbl text NOT NULL,
  beacon_id text NOT NULL,
  mutating_user text,
  txid bigint NOT NULL DEFAULT txid_current()
)
''');
  await writer.execute(r'''
CREATE OR REPLACE FUNCTION public.test_actor_probe_fn() RETURNS trigger
LANGUAGE plpgsql AS $$
BEGIN
  INSERT INTO public.test_actor_probe (tbl, beacon_id, mutating_user)
  VALUES (TG_TABLE_NAME, NEW.beacon_id,
          nullif(current_setting('tentura.mutating_user_id', true), ''));
  RETURN NEW;
END
$$
''');
  await writer.execute('''
CREATE TRIGGER test_actor_probe_offer
AFTER UPDATE ON public.beacon_help_offer
FOR EACH ROW WHEN (NEW.status = 1)
EXECUTE FUNCTION public.test_actor_probe_fn()
''');
  await writer.execute('''
CREATE TRIGGER test_actor_probe_commitment
AFTER INSERT ON public.beacon_commitment_event
FOR EACH ROW WHEN (NEW.kind = ${CommitmentEventKind.blockedCleanup.smallintValue})
EXECUTE FUNCTION public.test_actor_probe_fn()
''');
}

Future<List<_Probe>> _probes(Connection writer) async {
  final rows = await writer.execute(
    'SELECT tbl, beacon_id, mutating_user, txid '
    'FROM public.test_actor_probe ORDER BY seq',
  );
  return [
    for (final r in rows)
      (
        table: r[0]! as String,
        beaconId: r[1]! as String,
        mutatingUser: r[2] as String?,
        txid: r[3]! as int,
      ),
  ];
}

Future<int> _currentTxid(Connection writer) async =>
    (await writer.execute('SELECT txid_current()')).single.single! as int;

Future<({int status, String? withdrawReason})> _offer(
  Connection writer,
  String beaconId,
  String userId,
) async {
  final row = (await writer.execute(
    Sql.named(
      'SELECT status, withdraw_reason FROM public.beacon_help_offer '
      'WHERE beacon_id = @b AND user_id = @u',
    ),
    parameters: {'b': beaconId, 'u': userId},
  )).single;
  return (status: row[0]! as int, withdrawReason: row[1] as String?);
}

Future<List<({String actor, int kind, String? reason})>> _commitmentEvents(
  Connection writer,
  String beaconId,
  String userId,
) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT actor_user_id, kind, reason '
      'FROM public.beacon_commitment_event '
      'WHERE beacon_id = @b AND user_id = @u AND kind = @k ORDER BY seq',
    ),
    parameters: {
      'b': beaconId,
      'u': userId,
      'k': CommitmentEventKind.blockedCleanup.smallintValue,
    },
  );
  return [
    for (final r in rows)
      (actor: r[0]! as String, kind: r[1]! as int, reason: r[2] as String?),
  ];
}

Future<void> _seed(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.trust_evidence,
  public.user_block,
  public.inbox_item,
  public.beacon_forward_edge,
  public.beacon_participant,
  public.beacon,
  public."user"
CASCADE
''');
  final users = [_blocker, _blocked];
  for (var i = 0; i < users.length; i++) {
    await writer.execute(
      Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
      parameters: {'id': users[i], 'key': pgTestPublicKey('ubc', i + 1)},
    );
  }
  for (final (id, author) in [
    (_blockersRequest, _blocker),
    (_blockedsRequest, _blocked),
  ]) {
    await writer.execute('''
INSERT INTO public.beacon
  (id, user_id, title, description, status, is_discoverable, published_at)
VALUES ('$id', '$author', 'Move the piano', 'Saturday', 0, false, now())
''');
  }
}

final class _UnusedGenealogy extends Fake
    implements InviteGenealogyRepositoryPort {}
