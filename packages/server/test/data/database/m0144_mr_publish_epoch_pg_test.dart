@Tags(['pg'])
library;

import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart';
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/meritrank_repository.dart';
import 'package:tentura_server/data/repository/trust_evidence_repository.dart';
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
import 'package:tentura_server/domain/port/commitment_repository_port.dart';
import 'package:tentura_server/domain/port/forward_edge_repository_port.dart';
import 'package:tentura_server/domain/port/help_offer_repository_port.dart';
import 'package:tentura_server/domain/port/inbox_repository_port.dart';
import 'package:tentura_server/domain/port/mutating_unit_of_work_port.dart';
import 'package:tentura_server/domain/port/trust_maintenance_port.dart';
import 'package:tentura_server/domain/port/user_contact_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/user_block_case.dart';
import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';
import 'package:tentura_server/env.dart';

import '../../support/recording_commitment_repository.dart';
import '../../support/test_attention_harness.dart';

const _alice = 'Ucapb3alice01';
const _bob = 'Ucapb3bob0001';
const _ctx = '';

const _allIds = [_alice, _bob];

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late WitnessWindowRepository witnessWindow;
  late MeritrankRepository meritRank;
  late TrustEvidenceRepository trustEvidence;
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
      trustEvidence = TrustEvidenceRepository(database);
      trustEdgeRepo = UserTrustEdgeRepository(
        database,
        meritRank,
        trustEvidence,
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
      'trust_rebuild_effective_edge bumps epoch on successful publish',
      () async {
        expect(await _readEpoch(database), BigInt.zero);
        await _seedHonestTrustEdge(database, subject: _alice, object: _bob);
        expect(await _readEpoch(database), greaterThan(BigInt.zero));
      },
      skip: skipReason,
    );

    test(
      'trust_rebuild_effective_edge skips epoch bump when epsilon gate blocks publish',
      () async {
        await _seedHonestTrustEdge(database, subject: _alice, object: _bob);
        final afterFirst = await _readEpoch(database);

        await database.customSelect(
          r'SELECT trust_rebuild_effective_edge($1, $2)',
          variables: [
            Variable<String>(_alice),
            Variable<String>(_bob),
          ],
        ).getSingle();

        expect(await _readEpoch(database), afterFirst);
      },
      skip: skipReason,
    );

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
      'setUserVote bumps epoch and drops stale cached witness window',
      () async {
        await _seedCachedWindow(database, witnessWindow, ego: _alice);

        await trustEdgeCase.setUserVote(
          subjectUserId: _alice,
          objectUserId: _bob,
          amount: 1,
        );

        expect(await _readEpoch(database), greaterThan(BigInt.zero));
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
      'block bumps epoch and invalidates cached windows for both users',
      () async {
        await _seedHonestTrustEdge(database, subject: _alice, object: _bob);
        await _seedHonestTrustEdge(database, subject: _bob, object: _alice);
        await _seedCachedWindow(database, witnessWindow, ego: _alice);
        await _seedCachedWindow(database, witnessWindow, ego: _bob);
        final epochBefore = await _readEpoch(database);

        await blockCase.block(
          blockerId: _alice,
          blockedId: _bob,
          cascadeMode: 0,
        );

        expect(await _readEpoch(database), greaterThan(epochBefore));
        expect(await _windowRowCount(database), 0);
      },
      skip: skipReason,
    );

    test(
      'trust_rebuild_effective_edge does not bump epoch when mr_put_edge fails',
      () async {
        await database.customStatement(
          r'''
SELECT trust_apply_source_evidence(
  'personal', $1, $2, 'very_good', 2
)
''',
          [_alice, _bob],
        );
        final before = await _readEpoch(database);

        await writer.execute('DROP EXTENSION IF EXISTS pgmer2 CASCADE');
        await writer.execute('''
CREATE FUNCTION public.mr_put_edge(
  src text,
  dst text,
  weight double precision,
  context text,
  ticker bigint
) RETURNS void
LANGUAGE plpgsql
AS \$\$
BEGIN
  RAISE EXCEPTION 'b3 induced mr_put_edge failure';
END;
\$\$;
''');

        try {
          await database.customSelect(
            r'SELECT trust_rebuild_effective_edge($1, $2, $3)',
            variables: [
              Variable<String>(_alice),
              Variable<String>(_bob),
              const Variable<double>(-1),
            ],
          ).getSingle();
          expect(await _readEpoch(database), before);
        } finally {
          await writer.execute('DROP EXTENSION IF EXISTS pgmer2 CASCADE');
          await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
          await migrateDbSchema(writer);
        }
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
SELECT trust_apply_source_evidence(
  'personal', $1, $2, 'very_good', 2
)
''',
    [subject, object],
  );
  await db.customSelect(
    r'SELECT trust_rebuild_effective_edge($1, $2, $3)',
    variables: [
      Variable<String>(subject),
      Variable<String>(object),
      const Variable<double>(-1),
    ],
  ).getSingle();
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

Future<void> _clearMrEdge(TenturaDb db, String subject, String object) =>
    db.customStatement(
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
    'DELETE FROM public.user_trust_source_edge '
    'WHERE subject IN ($idList) OR object IN ($idList)',
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
  final row = await db
      .customSelect(
        r'''
SELECT count(*)::int AS c
FROM public.ego_witness_window
WHERE ego_user_id LIKE 'Ucapb3%'
''',
      )
      .getSingle();
  return row.read<int>('c');
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await connection.close();
    return true;
  } on Object {
    return false;
  }
}

class _DisposablePgTarget {
  const _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_MR_EPOCH_TEST_DB'] ??
        'tentura_test_mr_epoch_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_MR_EPOCH_TEST_DB',
        'must match tentura_test_[a-z0-9_]+ and be at most 63 characters',
      );
    }

    Env envFor(String database) => Env(
      environment: Environment.test,
      pgHost: host,
      pgPort: port,
      pgDatabase: database,
      pgUsername: username,
      pgPassword: password,
      printEnv: false,
      isDebugModeOn: false,
    );

    return _DisposablePgTarget(
      adminEnv: envFor(adminDatabase),
      databaseEnv: envFor(databaseName),
      databaseName: databaseName,
    );
  }

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  Future<void> recreate() async {
    final admin = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await admin.execute(
        'SELECT pg_terminate_backend(pid) FROM pg_stat_activity '
        "WHERE datname = '$databaseName' AND pid <> pg_backend_pid()",
      );
      await admin.execute('DROP DATABASE IF EXISTS "$databaseName"');
      await admin.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await admin.close();
    }
  }

  Future<void> drop() async {
    final admin = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await admin.execute(
        'SELECT pg_terminate_backend(pid) FROM pg_stat_activity '
        "WHERE datname = '$databaseName' AND pid <> pg_backend_pid()",
      );
      await admin.execute('DROP DATABASE IF EXISTS "$databaseName"');
    } finally {
      await admin.close();
    }
  }
}

final class _PassThroughUoW extends Fake implements MutatingUnitOfWorkPort {
  @override
  Future<T> run<T>({
    required Future<T> Function() action,
    String? actorUserId,
  }) =>
      action();
}

final class _FakeUsers extends Fake implements UserRepositoryPort {
  @override
  Future<UserEntity> getById(String id) async => UserEntity(id: id);
}

final class _FakeTrustMaintenance extends Fake
    implements TrustMaintenancePort {
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
  }) async =>
      [];
}

final class _FakeContacts extends Fake implements UserContactRepositoryPort {
  @override
  Future<bool> delete({
    required String viewerId,
    required String subjectId,
  }) async =>
      false;
}

final class _FakeBeacons extends Fake implements BeaconRepositoryPort {
  @override
  Future<BeaconEntity> getBeaconById({
    required String beaconId,
    String? filterByUserId,
  }) async =>
      BeaconEntity(
        id: beaconId,
        title: 't',
        author: UserEntity(id: 'unused'),
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        status: BeaconStatus.open,
      );
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
  }) async =>
      [];

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
