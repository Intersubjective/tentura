@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/domain/capability/context_normalization.dart';
import 'package:tentura_server/env.dart';

Future<void> main() async {
  final target = _DisposablePgTarget.fromEnvironment();
  final reachable = await _canConnect(target.adminEnv);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('cap_normalize_context SQL parity', () {
    late Connection writer;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    Future<String> sqlNormalize(String? input) async {
      final Result result;
      if (input == null) {
        result = await writer.execute(
          'SELECT public.cap_normalize_context(NULL)',
        );
      } else {
        result = await writer.execute(
          Sql.named('SELECT public.cap_normalize_context(@input)'),
          parameters: {'input': input},
        );
      }
      return result.single.single! as String;
    }

    for (final case_ in _parityCases) {
      test('parity for ${case_.label}', () async {
        final dart = capNormalizeContext(case_.input);
        final sql = await sqlNormalize(case_.input);
        expect(dart, case_.expected);
        expect(sql, case_.expected);
      }, skip: skipReason);
    }
  });
}

class _ParityCase {
  const _ParityCase(this.label, this.input, this.expected);

  final String label;
  final String? input;
  final String expected;
}

const _parityCases = [
  _ParityCase('null', null, ''),
  _ParityCase('empty', '', ''),
  _ParityCase('whitespace', '  ', ''),
  _ParityCase('two chars', 'ab', ''),
  _ParityCase('trimmed case', ' AbC ', 'AbC'),
  _ParityCase('32 chars', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'),
  _ParityCase('33 chars', 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa', ''),
];

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
        Platform.environment['TENTURA_M0142_CONTEXT_TEST_DB'] ??
        'tentura_test_m0142_ctx_${pid}_${DateTime.timestamp().microsecondsSinceEpoch}';
    if (!RegExp(r'^tentura_test_[a-z0-9_]+$').hasMatch(databaseName) ||
        databaseName.length > 63) {
      throw ArgumentError.value(
        databaseName,
        'TENTURA_M0142_CONTEXT_TEST_DB',
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
