@Tags(['pg', 'mr'])
library;

import 'package:drift/drift.dart' show Variable;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/trust_ledger_repository.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/user_block_repository.dart';
import 'package:tentura_server/data/repository/user_trust_edge_repository.dart';
import 'package:tentura_server/data/repository/witness_window_repository.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_server/domain/entity/beacon_entity.dart';
import 'package:tentura_server/domain/entity/forward_edge_entity.dart';
import 'package:tentura_server/domain/entity/help_offer_entity.dart';
import 'package:tentura_server/domain/entity/inbox_item_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/port/beacon_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/capability_evidence_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';

import '../../support/fake_beacon_hierarchy_repository.dart';
import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';

import '../../support/disposable_pg_target.dart';

const _alice = 'Ucapb3alice01';
const _bob = 'Ucapb3bob0001';
const _ctx = '';

const _allIds = [_alice, _bob];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_MR_EPOCH_TEST_DB',
    defaultNamePrefix: 'tentura_test_mr_epoch',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late WitnessWindowRepository witnessWindow;
  late MeritrankRepository meritRank;
  late UserTrustEdgeRepository trustEdgeRepo;
  late UserTrustEdgeCase trustEdgeCase;
  late UserBlockRepository blockRepo;
  late UserBlockCase blockCase;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      witnessWindow = WitnessWindowRepository(database);
      meritRank = MeritrankRepository(database);
      trustEdgeRepo = UserTrustEdgeRepository(
        database,
        meritRank,
        witnessWindow: witnessWindow,
      );
      final attention = TestAttentionHarness();
      trustEdgeCase = UserTrustEdgeCase(
        _FakeUsers(),
        trustEdgeRepo,
        _FakeTrustMaintenance(),
        attentionIntents: attention.intents,
        attention: attention.transactional,
        witnessWindow: witnessWindow,
        env: target.databaseEnv,
        logger: Logger('mr_publish_epoch_pg_test'),
      );
      blockRepo = UserBlockRepository(
        target.databaseEnv,
        database,
        witnessWindow: witnessWindow,
      );
      blockCase = UserBlockCase(
        _PassThroughUoW(),
        blockRepo,
        _FakeHelpOffers(),
        _FakeForwardEdges(),
        _FakeContacts(),
        _FakeUsers(),
        _FakeBeacons(),
        NoOpCommitmentRepository(),
        _FakeInbox(),
        _NoopCapabilityEvidence(),
        FakeBeaconHierarchyRepository(),
        trustLedger: TrustLedgerRepository(database),
        witnessWindow: witnessWindow,
        env: target.databaseEnv,
        logger: Logger('mr_publish_epoch_pg_test'),
      );
    });

    setUp(() async {
      await _cleanup(database, meritRank);
      await _resetEpoch(database);
      for (final id in _allIds) {
        await _insertUser(database, id);
      }
    });

    tearDown(() async {
      await _cleanup(database, meritRank);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  group('mr_publish_epoch SQL', () {
    test(
      'notify_meritrank_vote_user_mutation bumps epoch when wired to vote_user',
      () async {
        await database.customStatement('''
CREATE TRIGGER b3_test_notify_meritrank_vote_user_mutation
  AFTER INSERT OR UPDATE ON public.vote_user
  FOR EACH ROW EXECUTE FUNCTION public.notify_meritrank_vote_user_mutation();
''');
        expect(await _readEpoch(database), BigInt.zero);
        await database.customStatement('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$_alice', '$_bob', 1, now(), now())
''');
        expect(await _readEpoch(database), greaterThan(BigInt.zero));
      },
      skip: skipReason,
    );
  });

  group('mr_publish_epoch use cases', () {
    test(
      'setUserVote queues the pair, leaves the epoch to the publisher and drops '
      'stale cached witness window',
      () async {
        await _seedCachedWindow(database, witnessWindow, ego: _alice);

        await trustEdgeCase.setUserVote(
          subjectUserId: _alice,
          objectUserId: _bob,
          amount: 1,
        );

        // m0202: MR is fed out of transaction by the publisher, which owns
        // the epoch bump; the write path only queues the pair.
        expect(await _queuedPairs(database), [(_alice, _bob)]);
        expect(await _readEpoch(database), BigInt.zero);
        expect(
          await witnessWindow.cachedWindow(
            egoId: _alice,
            normalizedContext: _ctx,
          ),
          isEmpty,
        );
        expect(await _windowRowCount(database), 0);
      },
      skip: skipReason,
    );

    test(
      'block queues the withdrawal and invalidates cached windows for both '
      'users',
      () async {
        await _seedHonestTrustEdge(database, subject: _alice, object: _bob);
        await _seedHonestTrustEdge(database, subject: _bob, object: _alice);
        await _seedCachedWindow(database, witnessWindow, ego: _alice);
        await _seedCachedWindow(database, witnessWindow, ego: _bob);
        await database.customStatement(
          'DELETE FROM public.trust_publish_queue',
        );
        final epochBefore = await _readEpoch(database);

        await blockCase.block(
          blockerId: _alice,
          blockedId: _bob,
          cascadeMode: 0,
        );

        expect(await _queuedPairs(database), contains((_alice, _bob)));
        expect(await _readEpoch(database), epochBefore);
        expect(await _windowRowCount(database), 0);
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedHonestTrustEdge(
  TenturaDb db, {
  required String subject,
  required String object,
}) async {
  await db.customStatement(
    r'''
INSERT INTO public.trust_evidence
  (id, subject_user_id, object_user_id, kind, count, source_key)
VALUES ('m0144-ev-' || $1::text || '-' || $2::text, $1, $2, 2, 2,
        'm0144:' || $1::text || ':' || $2::text)
''',
    [subject, object],
  );
  await db
      .customSelect(
        r'SELECT public.trust_project_pair($1, $2)',
        variables: [Variable<String>(subject), Variable<String>(object)],
      )
      .getSingle();
  // The publisher is not running: stamp what it would have published.
  await db.customStatement(
    r'''
UPDATE public.user_trust_edge SET prev_sent_weight = target_w
WHERE subject = $1 AND object = $2
''',
    [subject, object],
  );
}

Future<void> _seedCachedWindow(
  TenturaDb db,
  WitnessWindowRepository repo, {
  required String ego,
}) async {
  await repo.storeWindow(
    egoId: ego,
    normalizedContext: _ctx,
    weights: const [
      WitnessWeight(
        witnessUserId: _bob,
        m: 1,
        admitted: true,
      ),
    ],
  );
  expect(await _windowRowCount(db), greaterThan(0));
}

Future<List<(String, String)>> _queuedPairs(TenturaDb db) async {
  final rows = await db.customSelect(
    r'''
SELECT subject_user_id, object_user_id
FROM public.trust_publish_queue
WHERE subject_user_id IN ('Ucapb3alice01', 'Ucapb3bob0001')
ORDER BY subject_user_id, object_user_id
''',
  ).get();
  return [
    for (final r in rows)
      (r.read<String>('subject_user_id'), r.read<String>('object_user_id')),
  ];
}

Future<BigInt> _readEpoch(TenturaDb db) async {
  final row = await db
      .customSelect(
        r'SELECT epoch FROM public.mr_publish_epoch WHERE id = true',
      )
      .getSingle();
  return row.read<BigInt>('epoch');
}

Future<void> _insertUser(TenturaDb db, String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

Future<void> _clearMrEdge(
  TenturaDb db,
  String subject,
  String object,
) => db.customStatement(
  "SELECT mr_put_edge('$subject', '$object', 0::double precision, ''::text, 0)",
);

Future<void> _cleanup(TenturaDb db, MeritrankRepository meritRank) async {
  for (final id in _allIds) {
    if (id == _alice) {
      for (final peer in _allIds.where((p) => p != _alice)) {
        await _clearMrEdge(db, _alice, peer);
        await _clearMrEdge(db, peer, _alice);
      }
    }
  }
  await db.customStatement(
    'DROP TRIGGER IF EXISTS b3_test_notify_meritrank_vote_user_mutation ON public.vote_user',
  );
  final idList = _allIds.map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.ego_witness_window '
    'WHERE ego_user_id IN ($idList) OR witness_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_block WHERE blocker_id IN ($idList) '
    'OR blocked_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_block_intent WHERE blocker_id IN ($idList) '
    'OR blocked_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.trust_publish_queue '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.trust_evidence '
    'WHERE subject_user_id IN ($idList) OR object_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_trust_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.vote_user '
    'WHERE subject IN ($idList) OR object IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public."user" WHERE id IN ($idList)',
  );
}

Future<void> _resetEpoch(TenturaDb db) => db.customStatement(
  r'UPDATE public.mr_publish_epoch SET epoch = 0 WHERE id = true',
);

Future<int> _windowRowCount(TenturaDb db) async {
  final row = await db.customSelect(
    r'''
SELECT count(*)::int AS c
FROM public.ego_witness_window
WHERE ego_user_id LIKE 'Ucapb3%'
''',
  ).getSingle();
  return row.read<int>('c');
}

final class _PassThroughUoW extends Fake implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) => action();
}

final class _FakeUsers extends Fake implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async => UserEntity(id: id);
}

final class _FakeTrustMaintenance extends Fake implements TrustMaintenancePort {
  @override
  Future<void> forceRefreshAll() async {}

  @override
  Future<void> runDue({DateTime? now}) async {}
}

final class _FakeHelpOffers extends Fake implements HelpOfferRepositoryPort {
  @override
  Future<List<HelpOfferEntity>> fetchByUserId(String userId) async => [];
}

final class _FakeForwardEdges extends Fake
    implements ForwardEdgeRepositoryPort {
  @override
  Future<List<ForwardEdgeEntity>> fetchByRecipientId(
    String recipientId, {
    String? context,
  }) async => [];
}

final class _FakeContacts extends Fake implements UserContactRepositoryPort {
  @override
  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  }) async => false;
}

final class _FakeBeacons extends Fake implements BeaconRepositoryPort {
  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async => BeaconEntity(
    id: beaconId,
    title: 't',
    author: UserEntity(id: 'unused'),
    createdAt: DateTime.utc(2026),
    updatedAt: DateTime.utc(2026),
    status: BeaconStatus.open,
  );
}

final class _NoopCapabilityEvidence extends Fake
    implements CapabilityEvidencePort {
  @override
  Future<void> reconcileForwardReasons({
    required String forwardEdgeId,
    required String observerId,
    required String subjectId,
    required List<String> slugs,
  }) async {}
}

final class _FakeInbox extends Fake implements InboxRepositoryPort {
  @override
  Future<void> upsertWatchingForSender({
    required String senderId,
    required String beaconId,
    String? context,
    bool touchForwardOrdering = true,
  }) async {}

  @override
  Future<void> applyTombstoneAfterWithdraw({
    required String userId,
    required String beaconId,
  }) async {}

  @override
  Future<void> markForwardCancelledForRecipient({
    required String beaconId,
    required String recipientId,
  }) async {}

  @override
  Future<List<InboxItemEntity>> fetchByUserId(
    String userId, {
    String? context,
    int limit = 50,
    int offset = 0,
  }) async => [];

  @override
  Future<List<String>> fetchRejectedUserIdsByBeacon(String beaconId) async =>
      [];

  @override
  Future<List<String>> fetchWatchingUserIdsByBeacon(String beaconId) async =>
      [];

  @override
  Future<void> setStatus({
    required String userId,
    required String beaconId,
    required int status,
    required String rejectionMessage,
  }) async {}
}
