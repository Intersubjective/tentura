import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';

import 'disposable_pg_target.dart';

/// Nothing listens on TCP port 1, so the admin probe is refused immediately.
DisposablePgTarget _unreachableTarget() {
  Env envFor(String database) => Env(
    environment: Environment.test,
    pgHost: '127.0.0.1',
    pgPort: 1,
    pgDatabase: database,
    pgUsername: 'postgres',
    pgPassword: 'password',
    printEnv: false,
    isDebugModeOn: false,
  );
  return DisposablePgTarget(
    adminEnv: envFor('postgres'),
    databaseEnv: envFor('tentura_test_required_mode'),
    templateEnv: envFor(templateDatabaseName),
    databaseName: 'tentura_test_required_mode',
    envVarName: 'TENTURA_REQUIRED_MODE_TEST_DB',
  );
}

void main() {
  group('pgSkipReason', () {
    test(
      'returns a skip reason when Postgres is unreachable and REQUIRED mode '
      'is not set',
      () async {
        final reason = await pgSkipReason(
          _unreachableTarget(),
          environment: const <String, String>{},
        );

        expect(reason, isNotNull);
        expect(reason, isNotEmpty);
      },
    );

    test(
      'returns a skip reason when REQUIRED mode is set to a value other '
      'than 1',
      () async {
        final reason = await pgSkipReason(
          _unreachableTarget(),
          environment: const {'TENTURA_PG_TESTS_REQUIRED': '0'},
        );

        expect(reason, isNotNull);
      },
    );

    test(
      'throws instead of skipping when Postgres is unreachable and '
      'TENTURA_PG_TESTS_REQUIRED=1',
      () async {
        await expectLater(
          pgSkipReason(
            _unreachableTarget(),
            environment: const {'TENTURA_PG_TESTS_REQUIRED': '1'},
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              'Postgres required (TENTURA_PG_TESTS_REQUIRED=1) but not '
                  'reachable',
            ),
          ),
        );
      },
    );
  });

  group('IsolatedHasuraSession.isDockerAvailable (via child process)', () {
    late Directory emptyPathDir;

    setUpAll(() {
      emptyPathDir = Directory.systemTemp.createTempSync('tentura_no_docker_');
    });

    tearDownAll(() {
      emptyPathDir.deleteSync(recursive: true);
    });

    /// Runs the probe with a PATH that contains no `docker` binary.
    Future<String> probeWithoutDocker({required bool required}) async {
      final result = await Process.run(
        Platform.resolvedExecutable,
        ['test/support/docker_availability_probe.dart'],
        environment: {
          'PATH': emptyPathDir.path,
          'TENTURA_PG_TESTS_REQUIRED': required ? '1' : '0',
        },
      );
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
      return (result.stdout as String).trim();
    }

    test(
      'returns false when docker is missing and REQUIRED mode is not set',
      () async {
        expect(await probeWithoutDocker(required: false), 'returned:false');
      },
    );

    test(
      'throws instead of returning false when docker is missing and '
      'TENTURA_PG_TESTS_REQUIRED=1',
      () async {
        expect(await probeWithoutDocker(required: true), startsWith('threw:'));
      },
    );
  });
}
