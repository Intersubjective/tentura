@Tags(['pg'])
library;

import 'dart:io';
import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/repository/beacon_room_repository.dart';
import 'package:tentura_server/env.dart';

import '../../support/pg_test_public_keys.dart';

void main() {
  final target = _DisposablePgTarget.fromEnvironment();
  late Connection writer;
  late TenturaDb database;
  late BeaconRoomRepository room;
  var available = false;
  var created = false;
  String? unavailableReason;

  setUpAll(() async {
    try {
      final probe = await Connection.open(
        target.adminEnv.pgEndpoint,
        settings: target.adminEnv.pgEndpointSettings,
      );
      await probe.close();
    } on SocketException catch (error) {
      unavailableReason = error.message;
      return;
    }

    await target.recreate();
    created = true;
    writer = await Connection.open(
      target.databaseEnv.pgEndpoint,
      settings: target.databaseEnv.pgEndpointSettings,
    );
    await writer.execute('SET check_function_bodies = false');
    await migrateDbSchema(writer);
    database = TenturaDb(target.databaseEnv);
    room = BeaconRoomRepository(database);
    available = true;
  });

  tearDownAll(() async {
    if (available) {
      await database.close();
      await writer.close();
    }
    if (created) await target.drop();
  });

  test('adds nullable jsonb mention_spans to beacon_room_message', () async {
    if (!available) {
      markTestSkipped('PostgreSQL unavailable: $unavailableReason');
    }
    final result = await writer.execute('''
SELECT data_type, udt_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'beacon_room_message'
  AND column_name = 'mention_spans'
''');
    expect(result, hasLength(1));
    final row = result.single;
    expect(row[0], 'jsonb');
    expect(row[1], 'jsonb');
    expect(row[2], 'YES');
  });

  test(
    'repository round-trips mention spans through jsonb projection',
    () async {
      if (!available) {
        markTestSkipped('PostgreSQL unavailable: $unavailableReason');
      }
      const beaconId = 'Bmigrationmention1';
      const authorId = 'Umigrationmention1';
      const mentionedId = 'Umigrationmention2';
      await database.customStatement('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('$authorId', 'Author', '${pgTestPublicKey('m0153', 1)}'),
  ('$mentionedId', 'Mentioned', '${pgTestPublicKey('m0153', 2)}')
''');
      await database.customStatement('''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES ('$beaconId', '$authorId', 'Mention migration', 'Roundtrip')
''');
      await database.customStatement('''
INSERT INTO public.beacon_participant (id, beacon_id, user_id, role, status, room_access)
VALUES
  ('Pmigrationmention1', '$beaconId', '$authorId', 2, 0, 3),
  ('Pmigrationmention2', '$beaconId', '$mentionedId', 2, 0, 3)
''');
      final message = await room.insertRoomMessage(
        beaconId: beaconId,
        authorId: authorId,
        body: '@Mentioned hello',
        mentionSpans: const [
          {'userId': mentionedId, 'offset': 0, 'length': 10},
        ],
      );
      expect((await room.getRoomMessageById(message.id))?.mentionSpans, [
        {'userId': mentionedId, 'offset': 0, 'length': 10},
      ]);
      final projection = (await room.listMessagesEnriched(
        beaconId: beaconId,
        viewerUserId: authorId,
        limit: 10,
      )).single;
      expect(jsonDecode(projection['mentionSpansJson']! as String), [
        {'userId': mentionedId, 'offset': 0, 'length': 10},
      ]);
    },
  );
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
        'tentura_test_m0153_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';

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
