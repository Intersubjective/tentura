@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/consts/coordination_item_consts.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for beacon_room_seen upsert PG test';

  group('BeaconRoomRepository.markBeaconRoomSeen — disposable Postgres', () {
    late Connection writer;
    late TenturaDb db;
    late BeaconRoomRepository room;

    const beaconId = 'Bseenpg000001';
    const userId = 'Useenpguser01';
    const askItemId = 'CIseenpgask01';

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      db = TenturaDb(target.databaseEnv);
      room = BeaconRoomRepository(db);
    });

    tearDown(() async {
      if (skipReason != false) {
        return;
      }
      await writer.execute(
        "DELETE FROM public.beacon_room_seen WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.coordination_item WHERE beacon_id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.beacon WHERE id = '$beaconId'",
      );
      await writer.execute(
        "DELETE FROM public.\"user\" WHERE id = '$userId'",
      );
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await db.close();
      await writer.close();
      await target.drop();
    });

    Future<void> seedUserAndBeacon() async {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'id': userId,
          'publicKey': pgTestPublicKey('seenpg', 1),
        },
      );
      await writer.execute(
        '''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES ('$beaconId', '$userId', 'Seen PG', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      );
    }

    Future<void> seedAskItem() async {
      await writer.execute(
        Sql.named(r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id,
  published, created_at, updated_at, published_at, source, ordering
) VALUES (
  @id, @beaconId, @kind, @status, 'Ask', '', @creatorId,
  true, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z',
  @source, 0
)
ON CONFLICT (id) DO NOTHING
'''),
        parameters: {
          'id': askItemId,
          'beaconId': beaconId,
          'kind': coordinationItemKindAsk,
          'status': coordinationItemStatusOpen,
          'creatorId': userId,
          'source': coordinationItemSourceDefault,
        },
      );
    }

    test(
      'beacon_room_seen has no primary key and both partial unique indexes exist',
      () async {
        if (skipReason != false) {
          return;
        }
        final pk = await writer.execute('''
SELECT 1
FROM pg_constraint
WHERE conrelid = 'public.beacon_room_seen'::regclass
  AND contype = 'p'
''');
        expect(pk, isEmpty);

        final indexes = await writer.execute('''
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND tablename = 'beacon_room_seen'
  AND indexname IN (
    'uq_beacon_room_seen_main',
    'uq_beacon_room_seen_thread'
  )
ORDER BY indexname
''');
        expect(
          indexes.map((r) => r[0]).toList(),
          ['uq_beacon_room_seen_main', 'uq_beacon_room_seen_thread'],
        );
      },
      skip: skipReason,
    );

    test(
      'General upsert returns persisted watermark on stale write',
      () async {
        if (skipReason != false) {
          return;
        }
        await seedUserAndBeacon();

        final newer = DateTime.utc(2026, 6, 1, 12);
        final stale = DateTime.utc(2026, 6, 1, 10);

        final first = await room.markBeaconRoomSeen(
          userId: userId,
          beaconId: beaconId,
          threadItemId: null,
          at: newer,
        );
        expect(first, newer);

        final second = await room.markBeaconRoomSeen(
          userId: userId,
          beaconId: beaconId,
          threadItemId: null,
          at: stale,
        );
        expect(second, newer);

        final stored = await writer.execute(
          Sql.named(r'''
SELECT last_seen_at
FROM public.beacon_room_seen
WHERE user_id = @userId
  AND beacon_id = @beaconId
  AND thread_item_id IS NULL
'''),
          parameters: {'userId': userId, 'beaconId': beaconId},
        );
        expect(stored, hasLength(1));
        expect(second.toUtc(), stored.first[0] as DateTime);
      },
      skip: skipReason,
    );

    test(
      'semantic thread upsert returns persisted watermark on stale write',
      () async {
        if (skipReason != false) {
          return;
        }
        await seedUserAndBeacon();
        await seedAskItem();

        final newer = DateTime.utc(2026, 6, 2, 12);
        final stale = DateTime.utc(2026, 6, 2, 9);

        final first = await room.markBeaconRoomSeen(
          userId: userId,
          beaconId: beaconId,
          threadItemId: askItemId,
          at: newer,
        );
        expect(first, newer);

        final second = await room.markBeaconRoomSeen(
          userId: userId,
          beaconId: beaconId,
          threadItemId: askItemId,
          at: stale,
        );
        expect(second, newer);

        final stored = await writer.execute(
          Sql.named(r'''
SELECT last_seen_at
FROM public.beacon_room_seen
WHERE user_id = @userId
  AND beacon_id = @beaconId
  AND thread_item_id = @threadItemId
'''),
          parameters: {
            'userId': userId,
            'beaconId': beaconId,
            'threadItemId': askItemId,
          },
        );
        expect(stored, hasLength(1));
        expect(second.toUtc(), stored.first[0] as DateTime);
      },
      skip: skipReason,
    );
  });
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

final class _DisposablePgTarget {
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
        Platform.environment['TENTURA_BEACON_ROOM_SEEN_PG_TEST_DB'] ??
        'tentura_test_broomseen_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_BEACON_ROOM_SEEN_PG_TEST_DB',
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
        'DROP DATABASE IF EXISTS $databaseName WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE $databaseName');
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
        'DROP DATABASE IF EXISTS $databaseName WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
