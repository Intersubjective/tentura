@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart';
import 'package:tentura_server/domain/constellation/constellation_field_selection.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late Connection writer;
  late TenturaDb db;

  const viewer = 'Upartviewer';
  const author = 'Upartauthor';
  const beaconId = 'Bparticip01';

  Future<void> insertUser(String id) => db.customStatement('''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ('$id', '$id', 'pk-$id', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');

  Future<void> insertBeacon({required String userId}) => db.customStatement('''
INSERT INTO public.beacon (
  id, user_id, title, description, status, is_discoverable,
  published_at, created_at, updated_at
) VALUES (
  '$beaconId', '$userId', 'title', 'desc', 0, true,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO UPDATE SET user_id = EXCLUDED.user_id
''');

  Future<bool> participates() async {
    final sql = constellationViewerParticipatesSql(
      viewerParam: r'$1',
      beaconAlias: 'b',
    );
    final row = await db.customSelect(
      '''
SELECT ($sql) AS participates
FROM public.beacon b
WHERE b.id = \$2
''',
      variables: [
        Variable.withString(viewer),
        Variable.withString(beaconId),
      ],
    ).getSingle();
    return row.read<bool>('participates');
  }

  if (skipReason == false) {
    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      db = TenturaDb(target.databaseEnv);
    });

    setUp(() async {
      await db.customStatement('DELETE FROM public.beacon_help_offer_coordination');
      await db.customStatement('DELETE FROM public.beacon_help_offer_admission_event');
      await db.customStatement('DELETE FROM public.beacon_commitment_event');
      await db.customStatement('DELETE FROM public.beacon_participant');
      await db.customStatement('DELETE FROM public.beacon_help_offer');
      await db.customStatement('DELETE FROM public.beacon_forward_edge');
      await db.customStatement('DELETE FROM public.beacon');
      await db.customStatement('DELETE FROM public."user"');
      await insertUser(viewer);
      await insertUser(author);
    });

    tearDownAll(() async {
      await db.close();
      await writer.close();
      await target.drop();
    });
  }

  group('constellationViewerParticipatesSql', () {
    test('uses disposable database', () async {
      final row = await db.customSelect('SELECT current_database() AS name').getSingle();
      expect(row.read<String>('name'), target.databaseName);
    }, skip: skipReason);

    test('author own beacon matches', () async {
      await insertBeacon(userId: viewer);
      expect(await participates(), isTrue);
    }, skip: skipReason);

    test('historical commitment event matches', () async {
      await insertBeacon(userId: author);
      await db.customStatement('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status, created_at, updated_at)
VALUES ('$beaconId', '$viewer', 'offer', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
      await db.customStatement('''
INSERT INTO public.beacon_commitment_event (
  id, beacon_id, user_id, actor_user_id, kind, created_at
) VALUES (
  'CEpart01', '$beaconId', '$viewer', '$author', 1, '2026-01-01T00:00:00Z'
)
''');
      expect(await participates(), isTrue);
    }, skip: skipReason);

    test('help offer admission event matches', () async {
      await insertBeacon(userId: author);
      await db.customStatement('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status, created_at, updated_at)
VALUES ('$beaconId', '$viewer', 'offer', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
      await db.customStatement('''
INSERT INTO public.beacon_help_offer_admission_event (
  id, beacon_id, offer_user_id, actor_user_id, action, seq, created_at
) VALUES (
  'AEpart01', '$beaconId', '$viewer', '$author', 0, 1, '2026-01-01T00:00:00Z'
)
''');
      expect(await participates(), isTrue);
    }, skip: skipReason);

    test('participant role or room access matches', () async {
      await insertBeacon(userId: author);
      await db.customStatement('''
INSERT INTO public.beacon_participant (
  beacon_id, user_id, role, room_access, created_at, updated_at
) VALUES (
  '$beaconId', '$viewer', 1, 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
''');
      expect(await participates(), isTrue);
    }, skip: skipReason);

    test('active help offer without decline matches', () async {
      await insertBeacon(userId: author);
      await db.customStatement('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status, created_at, updated_at)
VALUES ('$beaconId', '$viewer', 'offer', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
      expect(await participates(), isTrue);
    }, skip: skipReason);

    test('latest decline admission excludes participation', () async {
      await insertBeacon(userId: author);
      await db.customStatement('''
INSERT INTO public.beacon_help_offer (beacon_id, user_id, message, status, created_at, updated_at)
VALUES ('$beaconId', '$viewer', 'offer', 0, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''');
      await db.customStatement('''
INSERT INTO public.beacon_help_offer_admission_event (
  id, beacon_id, offer_user_id, actor_user_id, action, reason, seq, created_at
) VALUES (
  'AEpart02b', '$beaconId', '$viewer', '$author', 2, 'declined', 1, '2026-01-01T00:00:00Z'
)
''');
      expect(await participates(), isFalse);
    }, skip: skipReason);

    test('forward edge alone does not match', () async {
      await insertBeacon(userId: author);
      await db.customStatement('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  'FEpart01', '$beaconId', '$author', '$viewer', '2026-01-01T00:00:00Z', NULL
)
''');
      expect(await participates(), isFalse);
    }, skip: skipReason);

    test('unrelated viewer does not match', () async {
      await insertBeacon(userId: author);
      expect(await participates(), isFalse);
    }, skip: skipReason);
  });
}

final class _DisposablePgTarget {
  _DisposablePgTarget({
    required this.adminEnv,
    required this.databaseEnv,
    required this.databaseName,
  });

  final Env adminEnv;
  final Env databaseEnv;
  final String databaseName;

  factory _DisposablePgTarget.fromEnvironment() {
    final host = Platform.environment['POSTGRES_HOST'] ?? 'localhost';
    final port =
        int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432;
    final username = Platform.environment['POSTGRES_USERNAME'] ?? 'postgres';
    final password = Platform.environment['POSTGRES_PASSWORD'] ?? 'password';
    final adminDatabase =
        Platform.environment['POSTGRES_ADMIN_DBNAME'] ?? 'postgres';
    final databaseName =
        'tentura_test_cvp_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';

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

Future<bool> _canConnect(Env env) async {
  try {
    final conn = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    );
    await conn.close();
    return true;
  } on Object {
    return false;
  }
}
