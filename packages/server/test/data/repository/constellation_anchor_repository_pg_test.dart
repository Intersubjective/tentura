@Tags(['pg'])
library;

import 'dart:async';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart' hide ConstellationAnchor;
import 'package:tentura_server/data/database/postgres_serialization_retry.dart';
import 'package:tentura_server/data/repository/constellation_anchor_repository.dart';
import 'package:tentura_server/domain/entity/constellation_anchor.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('constellation anchor repository concurrency', () {
    late Connection writer;
    late TenturaDb db1;
    late TenturaDb db2;
    late ConstellationAnchorRepository repo1;
    late ConstellationAnchorRepository repo2;

    const viewer = 'Ucarepoview01';
    const person = 'Ucarepopeer01';
    const beacon = 'Bcarepobeac01';

    ConstellationAnchorPosition pos(double x, double y) =>
        ConstellationAnchorPosition(
          xUnits: x,
          yUnits: y,
          coordinateSpaceVersion: kConstellationCoordinateSpaceVersionV1,
        );

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      final proof = await writer.execute('SELECT current_database()');
      expect(proof.single.single, target.databaseName);

      await writer.execute('SET check_function_bodies = false');
      await writer.execute('CREATE EXTENSION IF NOT EXISTS pgmer2');
      await migrateDbSchema(writer);

      await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$viewer', '$viewer', 'pk', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
       ('$person', '$person', 'pk2', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING
''');
      await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$beacon', '$person', 't', 'd', 0, true,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT DO NOTHING
''');

      db1 = TenturaDb(target.databaseEnv);
      db2 = TenturaDb(target.databaseEnv);
      repo1 = ConstellationAnchorRepository(db1);
      repo2 = ConstellationAnchorRepository(db2);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE public.constellation_anchor, public.constellation_anchor_cursor CASCADE
''');
      await writer.execute('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$beacon', '$person', 't', 'd', 0, true,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
''');
    });

    tearDownAll(() async {
      await db1.close();
      await db2.close();
      await writer.close();
      await target.drop();
    });

    test('same-target concurrent upserts settle with last-write-wins ordering', () async {
      final results = await Future.wait([
        repo1.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.person(person),
          position: pos(1, 1),
        ),
        repo2.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.person(person),
          position: pos(2, 2),
        ),
      ]);
      final row = await writer.execute('''
SELECT x_units::float8, y_units::float8, revision
FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND person_id = '$person'
''');
      expect(row.length, 1);
      final revRaw = row.single[2];
      final rev = revRaw is BigInt ? revRaw : BigInt.from(revRaw as int);
      expect(rev, greaterThan(BigInt.zero));
      final maxResultRev = results
          .map((r) => r.anchor.revision.value)
          .reduce((a, b) => a > b ? a : b);
      expect(maxResultRev, rev);
    });

    test('delete-vs-move on different targets serializes under one cursor', () async {
      await repo1.upsertAnchor(
        viewerId: viewer,
        target: ConstellationAnchorTarget.person(person),
        position: pos(1, 1),
      );
      await repo1.upsertAnchor(
        viewerId: viewer,
        target: ConstellationAnchorTarget.beacon(beacon),
        position: pos(3, 3),
      );

      await Future.wait([
        repo1.deleteAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.person(person),
        ),
        repo2.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.beacon(beacon),
          position: pos(4, 4),
        ),
      ]);

      final personRows = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND person_id IS NOT NULL
''');
      expect(personRows.single.single, 0);
      final beaconRow = await writer.execute('''
SELECT x_units::float8 FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND beacon_id = '$beacon'
''');
      expect(beaconRow.single.single, 4.0);
    });

    test(
      'beacon cascade delete concurrent with person upsert completes via retry',
      () async {
        await repo1.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.beacon(beacon),
          position: pos(1, 1),
        );
        await repo1.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.person(person),
          position: pos(1, 1),
        );

        await Future.wait([
          writer.execute("DELETE FROM public.beacon WHERE id = '$beacon'"),
          repo2.upsertAnchor(
            viewerId: viewer,
            target: ConstellationAnchorTarget.person(person),
            position: pos(2, 2),
          ),
        ]);

        final anchors = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor WHERE viewer_id = '$viewer'
''');
        expect(anchors.single.single, 1);
        final personRow = await writer.execute('''
SELECT x_units::float8 FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND person_id = '$person'
''');
        expect(personRow.single.single, 2.0);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'person cascade delete concurrent with beacon upsert completes via retry',
      () async {
        const extraPerson = 'Ucarepopeer02';
        await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$extraPerson', '$extraPerson', 'pk3', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT DO NOTHING
''');
        await repo1.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.person(person),
          position: pos(1, 1),
        );
        await repo1.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.beacon(beacon),
          position: pos(1, 1),
        );
        await repo1.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.person(extraPerson),
          position: pos(0, 0),
        );

        await Future.wait([
          writer.execute(
            "DELETE FROM public.\"user\" WHERE id = '$extraPerson'",
          ),
          repo2.upsertAnchor(
            viewerId: viewer,
            target: ConstellationAnchorTarget.beacon(beacon),
            position: pos(5, 5),
          ),
        ]);

        final beaconRow = await writer.execute('''
SELECT x_units::float8 FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND beacon_id = '$beacon'
''');
        expect(beaconRow.single.single, 5.0);
        final extraRows = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND person_id = '$extraPerson'
''');
        expect(extraRows.single.single, 0);
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'upsert is deadlock victim: first transaction rolls back then one retry succeeds',
      () async {
        await repo1.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.beacon(beacon),
          position: pos(1, 1),
        );
        final revBefore = await repo1.readWatermark(viewer);
        final anchorReady = Completer<void>();
        final releaseAnchorLock = Completer<void>();

        final blocker = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        try {
          final holdAnchor = () async {
            await blocker.execute('BEGIN');
            await blocker.execute('''
SELECT id FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND beacon_id = '$beacon'
FOR UPDATE
''');
            anchorReady.complete();
            await releaseAnchorLock.future;
            await blocker.execute('''
SELECT viewer_id FROM public.constellation_anchor_cursor
WHERE viewer_id = '$viewer'
FOR UPDATE
''');
            await blocker.execute('COMMIT');
          }();

          await anchorReady.future;
          final upsertFuture = repo2.upsertAnchor(
            viewerId: viewer,
            target: ConstellationAnchorTarget.beacon(beacon),
            position: pos(9, 9),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          releaseAnchorLock.complete();
          await Future.wait([holdAnchor, upsertFuture]);

          final row = await writer.execute('''
SELECT x_units::float8, revision FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND beacon_id = '$beacon'
''');
          expect(row.length, 1);
          expect(row.single.first, 9.0);
          final revAfter = await repo1.readWatermark(viewer);
          expect(revAfter.value, greaterThan(revBefore.value));
        } finally {
          await blocker.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'cascade delete is deadlock victim without partial beacon removal',
      () async {
        await repo1.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.beacon(beacon),
          position: pos(1, 1),
        );
        final cursorReady = Completer<void>();
        final releaseCursorLock = Completer<void>();

        final blocker = await Connection.open(
          target.databaseEnv.pgEndpoint,
          settings: target.databaseEnv.pgEndpointSettings,
        );
        try {
          final holdCursor = () async {
            await blocker.execute('BEGIN');
            await blocker.execute('''
SELECT viewer_id FROM public.constellation_anchor_cursor
WHERE viewer_id = '$viewer'
FOR UPDATE
''');
            cursorReady.complete();
            await releaseCursorLock.future;
            await blocker.execute('COMMIT');
          }();

          await cursorReady.future;
          final deleteFuture = writer.execute(
            "DELETE FROM public.beacon WHERE id = '$beacon'",
          );
          final upsertFuture = repo2.upsertAnchor(
            viewerId: viewer,
            target: ConstellationAnchorTarget.person(person),
            position: pos(2, 2),
          );
          await Future<void>.delayed(const Duration(milliseconds: 20));
          releaseCursorLock.complete();
          await Future.wait([holdCursor, deleteFuture, upsertFuture]);

          final beaconRows = await writer.execute('''
SELECT count(*)::int FROM public.beacon WHERE id = '$beacon'
''');
          expect(beaconRows.single.single, 0);
          final anchorRows = await writer.execute('''
SELECT count(*)::int FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND beacon_id = '$beacon'
''');
          expect(anchorRows.single.single, 0);
        } finally {
          await blocker.close();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );

    test(
      'retry exhaustion leaves committed anchor state unchanged and emits nothing',
      () async {
        await repo1.upsertAnchor(
          viewerId: viewer,
          target: ConstellationAnchorTarget.person(person),
          position: pos(1, 1),
        );
        final deadlock = await _captureDeadlockException(target.databaseEnv);
        var attempts = 0;
        final failingRepo = ConstellationAnchorRepository(
          db1,
          transactionRetry: <T>(
            Future<T> Function() action, {
            int maxRetries = 1,
            bool Function(Object error)? isRetryable,
          }) =>
              withPostgresDeadlockOrSerializationRetry(
                () async {
                  attempts++;
                  if (attempts <= 2) {
                    throw deadlock;
                  }
                  return action();
                },
                maxRetries: maxRetries,
                isRetryable: (_) => true,
              ),
        );
        await expectLater(
          failingRepo.upsertAnchor(
            viewerId: viewer,
            target: ConstellationAnchorTarget.person(person),
            position: pos(8, 8),
          ),
          throwsA(predicate(isPostgresDeadlockOrSerializationFailure)),
        );
        expect(attempts, 2);
        final row = await writer.execute('''
SELECT x_units::float8 FROM public.constellation_anchor
WHERE viewer_id = '$viewer' AND person_id = '$person'
''');
        expect(row.single.single, 1.0);
      },
    );
  }, skip: skipReason);
}

Future<Object> _captureDeadlockException(Env env) async {
  final a = await Connection.open(
    env.pgEndpoint,
    settings: env.pgEndpointSettings,
  );
  final b = await Connection.open(
    env.pgEndpoint,
    settings: env.pgEndpointSettings,
  );
  try {
    await a.execute('BEGIN');
    await b.execute('BEGIN');
    await a.execute('SELECT pg_advisory_xact_lock(424242)');
    await b.execute('SELECT pg_advisory_xact_lock(424243)');
    Object? errA;
    Object? errB;
    await Future.wait([
      () async {
        try {
          await a.execute('SELECT pg_advisory_xact_lock(424243)');
        } on Object catch (error) {
          errA = error;
        }
      }(),
      () async {
        try {
          await b.execute('SELECT pg_advisory_xact_lock(424242)');
        } on Object catch (error) {
          errB = error;
        }
      }(),
    ]);
    final captured = errA ?? errB;
    if (captured == null) {
      throw StateError('expected deadlock');
    }
    expect(isPostgresDeadlockOrSerializationFailure(captured), isTrue);
    return captured;
  } finally {
    try {
      await a.execute('ROLLBACK');
    } on Object {
      // Transaction may already be aborted.
    }
    try {
      await b.execute('ROLLBACK');
    } on Object {
      // Transaction may already be aborted.
    }
    await a.close();
    await b.close();
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

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        Platform.environment['TENTURA_CONSTELLATION_ANCHOR_REPO_TEST_DB'] ??
        'tentura_test_carepo_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_CONSTELLATION_ANCHOR_REPO_TEST_DB',
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
