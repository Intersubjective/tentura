@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide ConstellationAnchor, isNotNull, isNull;
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/data/repository/read_snapshot_unit_of_work.dart';
import 'package:tentura_server/domain/entity/constellation_anchor.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('constellation anchor storage P02', () {
    late Connection writer;
    late Connection listener;
    late StreamSubscription<String> notificationSubscription;
    final notifications = <Map<String, dynamic>>[];

    late TenturaDb db;
    late ConstellationAnchorRepository repository;
    late ReadSnapshotUnitOfWork readSnapshots;

    const viewerA = 'Ucaanchorview01';
    const viewerB = 'Ucaanchorview02';
    const personP = 'Ucaanchorpers01';
    const personQ = 'Ucaanchorpers02';
    const beaconB = 'Bcaanchorbeac01';

    Future<void> seedUser(String id) => writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

    Future<void> seedBeacon(String id, String authorId) => writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$id', '$authorId', 't', 'd', 0, true,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
''');

    ConstellationAnchorPosition pos(double x, double y) =>
        ConstellationAnchorPosition(
          xUnits: x,
          yUnits: y,
          coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
        );

    List<Map<String, dynamic>> anchorNotifications() => notifications
        .where((m) => m['entity'] == 'constellation_anchor')
        .toList();

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      final dbName = await writer.execute('SELECT current_database()');
      expect(dbName.single.single, target.databaseName);

      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);

      listener = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await listener.execute('LISTEN entity_changes');
      notificationSubscription = listener.channels['entity_changes'].listen(
        (payload) => notifications.add(
          jsonDecode(payload) as Map<String, dynamic>,
        ),
      );
      await _settle();
      notifications.clear();

      db = TenturaDb(target.databaseEnv);
      repository = ConstellationAnchorRepository(db);
      readSnapshots = ReadSnapshotUnitOfWork(db);

      for (final id in [viewerA, viewerB, personP, personQ]) {
        await seedUser(id);
      }
      await seedBeacon(beaconB, personP);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE public.constellation_anchor, public.constellation_anchor_cursor CASCADE
''');
      notifications.clear();
    });

    tearDownAll(() async {
      await notificationSubscription.cancel();
      await listener.close();
      await db.close();
      await writer.close();
      await target.drop();
    });

    test('coordinate CHECK rejects NaN and both infinities per axis', () async {
      await seedUser(viewerA);
      for (final bad in [
        ("'NaN'::float8", '0'),
        ("'Infinity'::float8", '0'),
        ("'-Infinity'::float8", '0'),
        ('0', "'NaN'::float8"),
        ('0', "'Infinity'::float8"),
        ('0', "'-Infinity'::float8"),
      ]) {
        await expectLater(
          writer.execute('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  'CAcheck01', '$viewerA', '$personP', ${bad.$1}, ${bad.$2},
  1, 1, now()
)
'''),
          throwsA(isA<ServerException>()),
        );
      }
    });

    test('coordinate CHECK accepts envelope boundaries', () async {
      await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES ('$viewerA')
''');
      final fixtures = [
        (personP, -10.0, -10.0, 'CAedge01'),
        (personQ, 10.0, 10.0, 'CAedge02'),
        (beaconB, 0.0, 0.0, 'CAedge03'),
      ];
      for (final fixture in fixtures) {
        final personCol = fixture.$1 == beaconB ? 'NULL' : "'${fixture.$1}'";
        final beaconCol = fixture.$1 == beaconB ? "'$beaconB'" : 'NULL';
        await writer.execute('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, beacon_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  '${fixture.$4}', '$viewerA', $personCol, $beaconCol,
  ${fixture.$2}, ${fixture.$3}, 1, 1, now()
)
''');
      }
      final count = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor WHERE viewer_id = '$viewerA'
''');
      expect(count.single.single, 3);
    });

    test('partial unique indexes enforce one anchor per viewer target', () async {
      await writer.execute('''
INSERT INTO public.constellation_anchor_cursor (viewer_id) VALUES ('$viewerA')
''');
      await writer.execute('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  'CAuniq01', '$viewerA', '$personP', 1, 1, 1, 1, now()
)
''');
      await expectLater(
        writer.execute('''
INSERT INTO public.constellation_anchor (
  id, viewer_id, person_id, x_units, y_units,
  coordinate_space_version, revision, placed_at
) VALUES (
  'CAuniq02', '$viewerA', '$personP', 2, 2, 1, 2, now()
)
'''),
        throwsA(isA<ServerException>()),
      );
    });

    test('owner isolation: viewers do not share anchor rows', () async {
      final p = pos(1, 1);
      await repository.upsertAnchor(
        viewerId: viewerA,
        target: ConstellationAnchorTarget.person(personP),
        position: p,
      );
      await repository.upsertAnchor(
        viewerId: viewerB,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(2, 2),
      );
      final rows = await writer.execute('''
SELECT viewer_id, x_units FROM public.constellation_anchor
WHERE person_id = '$personP' ORDER BY viewer_id
''');
      expect(rows.length, 2);
      expect(rows.first[0], viewerA);
      expect(rows.last[0], viewerB);
    });

    test(
      'upsert move preserves anchor id and bumps account revision monotonically',
      () async {
        await repository.upsertAnchor(
          viewerId: viewerA,
          target: ConstellationAnchorTarget.person(personP),
          position: pos(1, 1),
        );
        final idAfterInsert = await writer.execute('''
SELECT id FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
        final anchorId = idAfterInsert.single.single as String;
        notifications.clear();
        final second = await repository.upsertAnchor(
          viewerId: viewerA,
          target: ConstellationAnchorTarget.person(personP),
          position: pos(3, 3),
        );
        expect(second.anchor.revision.value, greaterThan(BigInt.zero));
        expect(second.watermark.revision.value, second.anchor.revision.value);
        final idRows = await writer.execute('''
SELECT id FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
        expect(idRows.single.single, anchorId);
        final countRows = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
        expect(countRows.single.single, 1);
      },
    );

    test('placed_at is strictly increasing across rapid moves', () async {
      final a = await repository.upsertAnchor(
        viewerId: viewerA,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(1, 1),
      );
      final b = await repository.upsertAnchor(
        viewerId: viewerA,
        target: ConstellationAnchorTarget.person(personQ),
        position: pos(2, 2),
      );
      final c = await repository.upsertAnchor(
        viewerId: viewerA,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(1.5, 1.5),
      );
      expect(b.anchor.placedAt.isAfter(a.anchor.placedAt), isTrue);
      expect(c.anchor.placedAt.isAfter(b.anchor.placedAt), isTrue);
      expect(c.anchor.placedAt.isAfter(a.anchor.placedAt), isTrue);
    });

    test('delete existing row emits one lowercase delete notification', () async {
      await repository.upsertAnchor(
        viewerId: viewerA,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(1, 1),
      );
      notifications.clear();
      await repository.deleteAnchor(
        viewerId: viewerA,
        target: ConstellationAnchorTarget.person(personP),
      );
      await _waitUntil(() => anchorNotifications().isNotEmpty);
      expect(anchorNotifications().length, 1);
      expect(anchorNotifications().single['event'], 'delete');
      expect(anchorNotifications().single['id'], viewerA);
      expect(anchorNotifications().single['user_ids'], [viewerA]);
    });

    test('absent-key delete increments cursor once and emits one delete', () async {
      final before = await repository.readWatermark(viewerA);
      expect(before.value, BigInt.zero);
      notifications.clear();
      final result = await repository.deleteAnchor(
        viewerId: viewerA,
        target: ConstellationAnchorTarget.person(personP),
      );
      expect(result.watermark.revision.value, BigInt.one);
      await _waitUntil(() => anchorNotifications().isNotEmpty);
      expect(anchorNotifications().length, 1);
      final rows = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor WHERE viewer_id = '$viewerA'
''');
      expect(rows.single.single, 0);
    });

    test('aborted transaction emits no notification and rolls back cursor', () async {
      await repository.upsertAnchor(
        viewerId: viewerA,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(1, 1),
      );
      notifications.clear();
      await expectLater(
        db.withMutatingUser(viewerA, () async {
          await db.customStatement('''
INSERT INTO public.constellation_anchor_cursor (viewer_id)
VALUES (\$1) ON CONFLICT DO NOTHING
''', [viewerA]);
          await db.customStatement('''
SELECT viewer_id FROM public.constellation_anchor_cursor
WHERE viewer_id = \$1 FOR UPDATE
''', [viewerA]);
          await db.customStatement('''
UPDATE public.constellation_anchor
SET x_units = 9 WHERE viewer_id = \$1 AND person_id = \$2
''', [viewerA, personP]);
          throw StateError('abort');
        }),
        throwsA(isA<StateError>()),
      );
      await _settle();
      expect(anchorNotifications(), isEmpty);
      final coord = await writer.execute('''
SELECT x_units::float8 FROM public.constellation_anchor
WHERE viewer_id = '$viewerA' AND person_id = '$personP'
''');
      expect(coord.single.single, 1.0);
    });

    test('target person cascade removes anchor without double cursor bump', () async {
      await repository.upsertAnchor(
        viewerId: viewerA,
        target: ConstellationAnchorTarget.person(personQ),
        position: pos(1, 1),
      );
      final revBefore = await repository.readWatermark(viewerA);
      notifications.clear();
      await writer.execute(
        "DELETE FROM public.\"user\" WHERE id = '$personQ'",
      );
      await _settle();
      final remaining = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor WHERE viewer_id = '$viewerA'
''');
      expect(remaining.single.single, 0);
      final revAfter = await repository.readWatermark(viewerA);
      expect(revAfter.value, greaterThan(revBefore.value));
    });

    test('viewer delete removes cursor and anchors without recreate', () async {
      await repository.upsertAnchor(
        viewerId: viewerB,
        target: ConstellationAnchorTarget.person(personP),
        position: pos(1, 1),
      );
      await writer.execute(
        "DELETE FROM public.\"user\" WHERE id = '$viewerB'",
      );
      final cursor = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor_cursor
''');
      expect(cursor.single.single, 0);
    });

    test('withReadSnapshot uses repeatable read readonly transaction', () async {
      String? isolation;
      String? readOnly;
      await readSnapshots.withReadSnapshot(() async {
        final iso = await db.customSelect(
          "SELECT current_setting('transaction_isolation') AS v",
        ).getSingle();
        final ro = await db.customSelect(
          "SELECT current_setting('transaction_read_only') AS v",
        ).getSingle();
        isolation = iso.read<String>('v');
        readOnly = ro.read<String>('v');
        return null;
      });
      expect(isolation, contains('repeatable read'));
      expect(readOnly, 'on');
    });

    test('readWatermark returns zero without creating cursor row', () async {
      final watermark = await readSnapshots.withReadSnapshot(
        () => repository.readWatermark(viewerA),
      );
      expect(watermark.value, BigInt.zero);
      final rows = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor_cursor WHERE viewer_id = '$viewerA'
''');
      expect(rows.single.single, 0);
    });

    test('fresh migration through 0167 and upgrade from 0166 pre-feature', () async {
      final upgradeTarget = _DisposablePgTarget.fromEnvironment(
        suffix: '_upgrade',
      );
      await upgradeTarget.recreate();
      final upWriter = await Connection.open(
        upgradeTarget.databaseEnv.pgEndpoint,
        settings: upgradeTarget.databaseEnv.pgEndpointSettings,
      );
      try {
        await upWriter.execute('SET check_function_bodies = false');
        await migrateDbSchemaThrough(upWriter, '0166');
        final tables0166 = await upWriter.execute('''
SELECT to_regclass('public.constellation_anchor')
''');
        expect(tables0166.single.single, isNull);

        await migrateDbSchemaThrough(upWriter, '0167');
        final tables0167 = await upWriter.execute('''
SELECT to_regclass('public.constellation_anchor')
''');
        expect(tables0167.single.single, isNotNull);
      } finally {
        await upWriter.close();
        await upgradeTarget.drop();
      }
    });

    test(
      'readonly visibility cache miss does not write cache rows',
      () async {
        await writer.execute('''
INSERT INTO public.vote_user (subject, object, amount, created_at, updated_at)
VALUES ('$viewerA', '$personP', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$personP', '$viewerA', 1, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING
''');
        await writer.execute(
          "SELECT mr_put_edge('$viewerA', '$personP', 0.75::double precision, ''::text, 0)",
        );
        await writer.execute(
          'TRUNCATE public.person_mutual_visibility_cache',
        );
        final before = await writer.execute(
          'SELECT count(*)::int FROM public.person_mutual_visibility_cache',
        );
        expect(before.single.single, 0);

        final conn = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        try {
          await conn.execute('BEGIN');
          await conn.execute(
            'SET TRANSACTION ISOLATION LEVEL REPEATABLE READ READ ONLY',
          );
          final mutual = await conn.execute(
            Sql.named(
              r'''
SELECT public.person_are_mutually_visible_cached(@a, @b, @ctx) AS mutual
''',
            ),
            parameters: {'a': viewerA, 'b': personP, 'ctx': ''},
          );
          expect(mutual.single.first, isTrue);
          final mid = await conn.execute(
            'SELECT count(*)::int FROM public.person_mutual_visibility_cache',
          );
          expect(mid.single.single, 0);
          await conn.execute('COMMIT');
        } finally {
          await conn.close();
        }
      },
    );
  }, skip: skipReason);
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 100));

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Future<bool> _canConnect(Env env) async {
  try {
    final connection = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
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

  factory _DisposablePgTarget.fromEnvironment({String suffix = ''}) {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_CONSTELLATION_ANCHOR_TEST_DB'] ??
        'tentura_test_ca_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}$suffix';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_CONSTELLATION_ANCHOR_TEST_DB',
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
