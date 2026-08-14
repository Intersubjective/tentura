@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('m0149 resolution removal migration', () {
    late Connection writer;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    test(
      'disposable target uses an isolated database name',
      () {
        expect(target.databaseName, startsWith('tentura_test_'));
        expect(target.databaseName, isNot('postgres'));
        expect(target.databaseEnv.pgDatabase, target.databaseName);
      },
      skip: skipReason,
    );

    test(
      'deletes kind-4 items, cascades thread messages, keeps other kinds, ledgered once',
      () async {
        await migrateDbSchema(writer);

        await _seedResolutionRemovalFixture(writer);

        final kind4Before = await _countCoordinationItems(writer, kind: 4);
        final kind2Before = await _countCoordinationItems(writer, kind: 2);
        final messageBefore = await _countRoomMessages(
          writer,
          messageId: 'Rm0149msgres1',
        );
        expect(kind4Before, 1);
        expect(kind2Before, 1);
        expect(messageBefore, 1);

        for (final statement in m0149.statements) {
          await writer.execute(statement);
        }

        expect(await _countCoordinationItems(writer, kind: 4), 0);
        expect(await _countCoordinationItems(writer, kind: 2), 1);
        expect(
          await _countRoomMessages(writer, messageId: 'Rm0149msgres1'),
          0,
        );
        expect(
          await _countRoomMessages(writer, messageId: 'Rm0149msgask1'),
          1,
        );

        final ledgerRows = await writer.execute(
          "SELECT version FROM public.schema_version WHERE version = '0149'",
        );
        expect(ledgerRows.length, 1);

        await migrateDbSchema(writer);
        final ledgerAfter = await writer.execute(
          "SELECT version FROM public.schema_version WHERE version = '0149'",
        );
        expect(ledgerAfter.length, 1);
      },
      skip: skipReason,
    );
  });
}

Future<void> _seedResolutionRemovalFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES
  ('Um0149auth1', 'Author', 'pk-m0149-auth', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''');
  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description, created_at, updated_at)
VALUES (
  'Bm0149bcn1', 'Um0149auth1', 'Resolution removal', '', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'
)
ON CONFLICT (id) DO NOTHING
''');
  await writer.execute(r'''
INSERT INTO public.coordination_item (
  id, beacon_id, kind, status, title, body, creator_id, target_person_id,
  target_item_id, published, created_at, updated_at, published_at, source, ordering
) VALUES
  (
    'Im0149ask01', 'Bm0149bcn1', 2, 0, 'Ask item', '', 'Um0149auth1', 'Um0149auth1', NULL, true,
    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', 0, 0
  ),
  (
    'Im0149res01', 'Bm0149bcn1', 4, 0, 'Resolution item', '', 'Um0149auth1', NULL, 'Im0149ask01', true,
    '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z', '2026-01-02T00:00:00Z', 0, 0
  )
ON CONFLICT (id) DO NOTHING
''');
  await writer.execute(r'''
INSERT INTO public.beacon_room_message (
  id, beacon_id, author_id, body, thread_item_id, created_at
) VALUES
  (
    'Rm0149msgask1', 'Bm0149bcn1', 'Um0149auth1', 'Ask thread message', 'Im0149ask01',
    '2026-01-01T01:00:00Z'
  ),
  (
    'Rm0149msgres1', 'Bm0149bcn1', 'Um0149auth1', 'Resolution thread message', 'Im0149res01',
    '2026-01-02T01:00:00Z'
  )
ON CONFLICT (id) DO NOTHING
''');
}

Future<int> _countCoordinationItems(
  Connection writer, {
  required int kind,
}) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT count(*)::int AS n FROM public.coordination_item WHERE kind = @kind',
    ),
    parameters: {'kind': kind},
  );
  return rows.single[0] as int;
}

Future<int> _countRoomMessages(
  Connection writer, {
  required String messageId,
}) async {
  final rows = await writer.execute(
    Sql.named(
      'SELECT count(*)::int AS n FROM public.beacon_room_message WHERE id = @id',
    ),
    parameters: {'id': messageId},
  );
  return rows.single[0] as int;
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
        Platform.environment['TENTURA_RESOLUTION_REMOVAL_MIGRATION_TEST_DB'] ??
        'tentura_test_m0149_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_RESOLUTION_REMOVAL_MIGRATION_TEST_DB',
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
        'DROP DATABASE IF EXISTS ${databaseName} WITH (FORCE)',
      );
      await connection.execute('CREATE DATABASE ${databaseName}');
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
        'DROP DATABASE IF EXISTS ${databaseName} WITH (FORCE)',
      );
    } finally {
      await connection.close();
    }
  }
}
