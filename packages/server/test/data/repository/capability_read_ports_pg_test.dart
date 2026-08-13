@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/capability_own_evidence_repository.dart';
import 'package:tentura_server/data/repository/capability_telemetry_repository.dart';
import 'package:tentura_server/data/repository/pair_block_query_repository.dart';
import 'package:tentura_server/data/repository/routing_mute_repository.dart';
import 'package:tentura_server/domain/capability/capability_evidence_models.dart';
import 'package:tentura_server/env.dart';

const _ego = 'Ucapb2cego01';
const _sub1 = 'Ucapb2csub01';
const _sub2 = 'Ucapb2csub02';
const _userA = 'Ucapb2cusrA1';
const _userB = 'Ucapb2cusrB1';
const _userC = 'Ucapb2cusrC1';

const _allIds = [_ego, _sub1, _sub2, _userA, _userB, _userC];

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb database;
  late CapabilityOwnEvidenceRepository ownEvidenceRepo;
  late RoutingMuteRepository muteRepo;
  late CapabilityTelemetryRepository telemetryRepo;
  late PairBlockQueryRepository blockRepo;

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      ownEvidenceRepo = CapabilityOwnEvidenceRepository(database);
      muteRepo = RoutingMuteRepository(database);
      telemetryRepo = CapabilityTelemetryRepository(database);
      blockRepo = PairBlockQueryRepository(database);
    });

    setUp(() async {
      await _cleanup(database);
      for (final id in _allIds) {
        await _insertUser(database, id);
      }
    });

    tearDown(() async {
      await _cleanup(database);
    });

    tearDownAll(() async {
      await database.close();
      await writer.close();
      await target.drop();
    });
  }

  group('CapabilityOwnEvidenceRepository', () {
    test(
      'fetchOwnEvidence maps source types to channels and excludes legacy rows',
      () async {
        await _insertCapabilityEvent(
          database,
          id: 'CEb2c0001',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'pets',
          sourceType: 3,
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2c0002',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'transport',
          sourceType: 1,
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2c0003',
          observerId: _ego,
          subjectId: _sub2,
          tagSlug: 'pets',
          sourceType: 4,
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2c0004',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'money',
          sourceType: 2,
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2c0005',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'housing',
          sourceType: 0,
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2c0006',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'pets',
          sourceType: 3,
          deleted: true,
        );

        final rows = await ownEvidenceRepo.fetchOwnEvidence(
          egoId: _ego,
          subjectIds: [_sub1, _sub2],
          tagSlugs: ['pets', 'transport', 'money', 'housing'],
        );

        expect(
          rows,
          [
            OwnEvidenceRow(
              subjectUserId: _sub1,
              tagSlug: 'pets',
              channel: EvidenceChannel.outcome,
            ),
            OwnEvidenceRow(
              subjectUserId: _sub1,
              tagSlug: 'transport',
              channel: EvidenceChannel.seed,
            ),
            OwnEvidenceRow(
              subjectUserId: _sub2,
              tagSlug: 'pets',
              channel: EvidenceChannel.seed,
            ),
          ],
        );
      },
      skip: skipReason,
    );

    test(
      'fetchOwnEvidence returns empty for empty filters',
      () async {
        expect(
          await ownEvidenceRepo.fetchOwnEvidence(
            egoId: _ego,
            subjectIds: const [],
            tagSlugs: ['pets'],
          ),
          isEmpty,
        );
        expect(
          await ownEvidenceRepo.fetchOwnEvidence(
            egoId: _ego,
            subjectIds: [_sub1],
            tagSlugs: const [],
          ),
          isEmpty,
        );
      },
      skip: skipReason,
    );

    test(
      'fetchTombstones returns active suppressions for ego subjects',
      () async {
        await _insertCapabilityEvent(
          database,
          id: 'CEb2c0101',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'pets',
          sourceType: 0,
          isNegative: true,
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2c0102',
          observerId: _ego,
          subjectId: _sub2,
          tagSlug: 'transport',
          sourceType: 0,
          isNegative: true,
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2c0103',
          observerId: _ego,
          subjectId: _sub2,
          tagSlug: 'money',
          sourceType: 0,
          isNegative: true,
          deleted: true,
        );

        final tombstones = await ownEvidenceRepo.fetchTombstones(
          egoId: _ego,
          subjectIds: [_sub1, _sub2],
        );

        expect(
          tombstones,
          [
            TombstoneRef(subjectUserId: _sub1, tagSlug: 'pets'),
            TombstoneRef(subjectUserId: _sub2, tagSlug: 'transport'),
          ],
        );
      },
      skip: skipReason,
    );

    test(
      'fetchTombstones returns empty for empty subjectIds',
      () async {
        expect(
          await ownEvidenceRepo.fetchTombstones(
            egoId: _ego,
            subjectIds: const [],
          ),
          isEmpty,
        );
      },
      skip: skipReason,
    );
  });

  group('RoutingMuteRepository', () {
    test(
      'mutedSlugsFor returns subject-keyed slug sets',
      () async {
        await muteRepo.setMute(
          userId: _sub1,
          tagSlug: 'pets',
          muted: true,
        );
        await muteRepo.setMute(
          userId: _sub1,
          tagSlug: 'transport',
          muted: true,
        );
        await muteRepo.setMute(
          userId: _sub2,
          tagSlug: 'pets',
          muted: true,
        );

        final muted = await muteRepo.mutedSlugsFor(subjectIds: [_sub1, _sub2]);

        expect(muted[_sub1], {'pets', 'transport'});
        expect(muted[_sub2], {'pets'});
        expect(muted.containsKey(_ego), isFalse);
      },
      skip: skipReason,
    );

    test(
      'mutedSlugsForUser and setMute are idempotent',
      () async {
        await muteRepo.setMute(
          userId: _sub1,
          tagSlug: 'pets',
          muted: true,
        );
        await muteRepo.setMute(
          userId: _sub1,
          tagSlug: 'pets',
          muted: true,
        );
        expect(await muteRepo.mutedSlugsForUser(_sub1), {'pets'});

        await muteRepo.setMute(
          userId: _sub1,
          tagSlug: 'pets',
          muted: false,
        );
        await muteRepo.setMute(
          userId: _sub1,
          tagSlug: 'pets',
          muted: false,
        );
        expect(await muteRepo.mutedSlugsForUser(_sub1), isEmpty);
      },
      skip: skipReason,
    );

    test(
      'mutedSlugsFor returns empty map for empty subjectIds',
      () async {
        expect(
          await muteRepo.mutedSlugsFor(subjectIds: const []),
          isEmpty,
        );
      },
      skip: skipReason,
    );

    test(
      'muteCountsByTag returns per-tag population counts only',
      () async {
        await muteRepo.setMute(userId: _sub1, tagSlug: 'pets', muted: true);
        await muteRepo.setMute(userId: _sub2, tagSlug: 'pets', muted: true);
        await muteRepo.setMute(userId: _sub1, tagSlug: 'transport', muted: true);

        final counts = await muteRepo.muteCountsByTag();

        expect(counts, {'pets': 2, 'transport': 1});
      },
      skip: skipReason,
    );
  });

  group('CapabilityTelemetryRepository', () {
    test(
      'countSeedRenewal counts forward-reason renewal before cell expiry',
      () async {
        await _insertCapabilityEvent(
          database,
          id: 'CEb2cseed1',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'pets',
          sourceType: 4,
          createdAt: '2026-01-01T00:00:00Z',
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2cseed2',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'pets',
          sourceType: 1,
          createdAt: '2026-02-01T00:00:00Z',
        );
        await _insertCapabilityEdge(
          database,
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'pets',
          nextExpiryAt: '2026-06-01T00:00:00Z',
        );

        final counts = await telemetryRepo.countSeedRenewal();

        expect(counts.seedTriples, 1);
        expect(counts.renewed, 1);
      },
      skip: skipReason,
    );

    test(
      'countSeedRenewal ignores renewal after next_expiry_at',
      () async {
        await _insertCapabilityEvent(
          database,
          id: 'CEb2cseed3',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'transport',
          sourceType: 4,
          createdAt: '2026-01-01T00:00:00Z',
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2cseed4',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'transport',
          sourceType: 1,
          createdAt: '2026-07-01T00:00:00Z',
        );
        await _insertCapabilityEdge(
          database,
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'transport',
          nextExpiryAt: '2026-06-01T00:00:00Z',
        );

        final counts = await telemetryRepo.countSeedRenewal();

        expect(counts.seedTriples, 1);
        expect(counts.renewed, 0);
      },
      skip: skipReason,
    );

    test(
      'countSeedRenewal treats null next_expiry_at as not yet expired',
      () async {
        await _insertCapabilityEvent(
          database,
          id: 'CEb2cseed5',
          observerId: _ego,
          subjectId: _sub2,
          tagSlug: 'pets',
          sourceType: 4,
          createdAt: '2026-01-01T00:00:00Z',
        );
        await _insertCapabilityEvent(
          database,
          id: 'CEb2cseed6',
          observerId: _ego,
          subjectId: _sub2,
          tagSlug: 'pets',
          sourceType: 1,
          createdAt: '2026-08-01T00:00:00Z',
        );

        final counts = await telemetryRepo.countSeedRenewal();

        expect(counts.seedTriples, 1);
        expect(counts.renewed, 1);
      },
      skip: skipReason,
    );

    test(
      'countSeedRenewal excludes privateLabel-only triples',
      () async {
        await _insertCapabilityEvent(
          database,
          id: 'CEb2cseed7',
          observerId: _ego,
          subjectId: _sub1,
          tagSlug: 'pets',
          sourceType: 0,
          createdAt: '2026-01-01T00:00:00Z',
        );

        final counts = await telemetryRepo.countSeedRenewal();

        expect(counts.seedTriples, 0);
        expect(counts.renewed, 0);
      },
      skip: skipReason,
    );
  });

  group('PairBlockQueryRepository', () {
    test(
      'blockedPairsAmong returns lexicographic pairs within the batch',
      () async {
        await _insertBlock(database, blockerId: _userA, blockedId: _userB);
        await _insertBlock(database, blockerId: _userC, blockedId: _userA);

        final blocked = await blockRepo.blockedPairsAmong(
          userIds: {_userA, _userB, _userC},
        );

        expect(blocked, {(_userA, _userB), (_userA, _userC)});
      },
      skip: skipReason,
    );

    test(
      'blockedPairsAmong ignores pairs with an endpoint outside the batch',
      () async {
        await _insertBlock(database, blockerId: _userA, blockedId: _userB);

        final blocked = await blockRepo.blockedPairsAmong(userIds: {_userA});

        expect(blocked, isEmpty);
      },
      skip: skipReason,
    );

    test(
      'blockedPairsAmong returns empty for fewer than two userIds',
      () async {
        expect(
          await blockRepo.blockedPairsAmong(userIds: const {}),
          isEmpty,
        );
        expect(
          await blockRepo.blockedPairsAmong(userIds: {_userA}),
          isEmpty,
        );
      },
      skip: skipReason,
    );
  });
}

Future<void> _insertUser(TenturaDb db, String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

Future<void> _insertCapabilityEvent(
  TenturaDb db, {
  required String id,
  required String observerId,
  required String subjectId,
  required String tagSlug,
  required int sourceType,
  bool isNegative = false,
  bool deleted = false,
  String createdAt = '2026-01-01T00:00:00Z',
}) => db.customStatement('''
INSERT INTO public.person_capability_event (
  id, subject_user_id, observer_user_id, tag_slug, source_type,
  visibility, is_negative, deleted_at, created_at
) VALUES (
  '$id', '$subjectId', '$observerId', '$tagSlug', $sourceType,
  0, $isNegative, ${deleted ? "'2026-01-01T00:00:00Z'" : 'NULL'}, '$createdAt'
)
''');

Future<void> _insertCapabilityEdge(
  TenturaDb db, {
  required String observerId,
  required String subjectId,
  required String tagSlug,
  String? nextExpiryAt,
}) => db.customStatement('''
INSERT INTO public.capability_evidence_edge (
  observer_user_id, subject_user_id, tag_slug, next_expiry_at
) VALUES (
  '$observerId', '$subjectId', '$tagSlug',
  ${nextExpiryAt == null ? 'NULL' : "'$nextExpiryAt'"}
)
ON CONFLICT (observer_user_id, subject_user_id, tag_slug) DO UPDATE
SET next_expiry_at = EXCLUDED.next_expiry_at
''');

Future<void> _insertBlock(
  TenturaDb db, {
  required String blockerId,
  required String blockedId,
}) => db.customStatement('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES ('$blockerId', '$blockedId', '$blockerId')
ON CONFLICT DO NOTHING
''');

Future<void> _cleanup(TenturaDb db) async {
  final idList = _allIds.map((id) => "'$id'").join(', ');
  await db.customStatement(
    'DELETE FROM public.capability_evidence_edge '
    'WHERE observer_user_id IN ($idList) OR subject_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.person_capability_event '
    'WHERE observer_user_id IN ($idList) OR subject_user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.capability_routing_mute WHERE user_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public.user_block '
    'WHERE blocker_id IN ($idList) OR blocked_id IN ($idList)',
  );
  await db.customStatement(
    'DELETE FROM public."user" WHERE id IN ($idList)',
  );
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
        Platform.environment['TENTURA_CAPABILITY_READ_PORTS_TEST_DB'] ??
        'tentura_test_cap_read_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_CAPABILITY_READ_PORTS_TEST_DB',
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
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE "$databaseName"');
    } finally {
      await connection.close();
    }
  }

  Future<void> drop() async {
    final connection = await Connection.open(
      adminEnv.pgEndpoint,
      settings: adminEnv.pgEndpointSettings,
    );
    try {
      await connection.execute(
        'DROP DATABASE IF EXISTS "$databaseName" WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
