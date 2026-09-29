// tentura-50o: Hasura pg harness JWT keys must load without repo `.env` or
// process JWT_* env vars (fresh checkout / worktree).

import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

import 'beacon_hierarchy_fixture.dart';
import 'hasura_pg_jwt_keys.dart';
import 'isolated_hasura_session.dart';

const _kDefaultPathProbeRelative =
    'test/support/hasura_pg_jwt_default_path_probe_test.dart';
const _kDefaultPathProbeName =
    'tentura-50o loadJwtKeysForHasuraPgTests default path fresh checkout';

const _kHasuraJwtStateErrorMarkers = <String>[
  'JWT_PUBLIC_PEM/JWT_PRIVATE_PEM required for Hasura JWT parity test',
  'JWT_PUBLIC_PEM/JWT_PRIVATE_PEM required for Hasura access test',
];

const _markerPublic =
    r'-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA2CmIb3Ho2eb6m8WIog6KiyzCY05sbyX04PiGlH5baDw=\n-----END PUBLIC KEY-----';
const _markerPrivate =
    r'-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIN3rCo3wCksyxX4qBYAC1vFr51kx/Od78QVrRLOV1orF\n-----END PRIVATE KEY-----';

void main() async {
  final postgresReachable = await canConnectBeaconHierarchyPostgres();
  final dockerReachable =
      postgresReachable && await IsolatedHasuraSession.isDockerAvailable();
  final hasuraPgHarnessSkip = !postgresReachable || !dockerReachable
      ? 'Postgres admin database and Docker required for beacon Hasura pg setUpAll subprocess harness'
      : false;

  group('tentura-50o loadJwtKeysForHasuraPgTests default resolution (production setUpAll)', () {
    test(
      'subprocess loads JWT with null overrides when repo .env is absent and JWT env is empty',
      () async {
        final outcome = await _runFreshCheckoutDartTest([
          _kDefaultPathProbeRelative,
          '--plain-name',
          _kDefaultPathProbeName,
        ]);
        for (final marker in _kHasuraJwtStateErrorMarkers) {
          expect(
            outcome.combined,
            isNot(contains(marker)),
            reason:
                'default-path loader must not throw JWT StateError on fresh checkout '
                '(exit ${outcome.exitCode}, output:\n${outcome.combined})',
          );
        }
        expect(
          outcome.exitCode,
          0,
          reason:
              'default-path probe must pass when tentura-50o fallback is implemented '
              '(output:\n${outcome.combined})',
        );
      },
      timeout: const Timeout(Duration(minutes: 8)),
    );
  });

  group('tentura-50o loadJwtKeysForHasuraPgTests override hooks (regression)', () {
    test('uses embedded test keys when repo .env is missing and JWT env is empty', () {
      final keys = loadJwtKeysForHasuraPgTests(
        repoDotEnvOverride: File(
          p.join(
            Directory.systemTemp.path,
            'missing-tentura-env-${DateTime.timestamp().microsecondsSinceEpoch}',
          ),
        ),
        platformEnvironmentOverride: const {},
      );

      final expectedPublic = Env.kJwtPublicKey.replaceAll(r'\n', '\n');
      final expectedPrivate = Env.kJwtPrivateKey.replaceAll(r'\n', '\n');

      expect(keys.publicKey.replaceAll(r'\n', '\n'), equals(expectedPublic));
      expect(keys.privateKey.replaceAll(r'\n', '\n'), equals(expectedPrivate));
      expect(EdDSAPublicKey.fromPEM(keys.publicKey).bytes, isNotEmpty);
      expect(EdDSAPrivateKey.fromPEM(keys.privateKey).seed, isNotEmpty);
    });

    test(
      'uses process JWT env when repo .env is missing and platformEnvironmentOverride supplies PEMs',
      () {
        final keys = loadJwtKeysForHasuraPgTests(
          repoDotEnvOverride: File(
            p.join(
              Directory.systemTemp.path,
              'missing-tentura-env-${DateTime.timestamp().microsecondsSinceEpoch}',
            ),
          ),
          platformEnvironmentOverride: const {
            'JWT_PUBLIC_PEM': _markerPublic,
            'JWT_PRIVATE_PEM': _markerPrivate,
          },
        );

        expect(keys.publicKey, equals(_markerPublic));
        expect(keys.privateKey, equals(_markerPrivate));
      },
    );

    test('uses embedded test keys when repo .env exists but omits JWT PEM entries', () async {
      final dir = await Directory.systemTemp.createTemp('tentura-hasura-jwt-');
      addTearDown(() => dir.delete(recursive: true));
      final dotEnv = File(p.join(dir.path, '.env'));
      await dotEnv.writeAsString('PG_HOST=127.0.0.1\n# no JWT keys\n');

      final keys = loadJwtKeysForHasuraPgTests(
        repoDotEnvOverride: dotEnv,
        platformEnvironmentOverride: const {},
      );

      expect(
        keys.publicKey.replaceAll(r'\n', '\n'),
        equals(Env.kJwtPublicKey.replaceAll(r'\n', '\n')),
      );
      expect(
        keys.privateKey.replaceAll(r'\n', '\n'),
        equals(Env.kJwtPrivateKey.replaceAll(r'\n', '\n')),
      );
    });

    test('prefers JWT PEM values from repo .env when present', () async {
      final dir = await Directory.systemTemp.createTemp('tentura-hasura-jwt-');
      addTearDown(() => dir.delete(recursive: true));
      final dotEnv = File(p.join(dir.path, '.env'));
      await dotEnv.writeAsString(
        'JWT_PUBLIC_PEM=$_markerPublic\nJWT_PRIVATE_PEM=$_markerPrivate\n',
      );

      final keys = loadJwtKeysForHasuraPgTests(
        repoDotEnvOverride: dotEnv,
        platformEnvironmentOverride: const {},
      );

      expect(keys.publicKey, equals(_markerPublic.replaceAll(r'\n', '\n')));
      expect(keys.privateKey, equals(_markerPrivate.replaceAll(r'\n', '\n')));
    });
  });

  group('tentura-50o beacon Hasura pg files use shared loader in setUpAll', () {
    const apiTestRelatives = <String>[
      'test/api/beacon_access_hasura_test.dart',
      'test/api/beacon_hierarchy_hasura_parity_test.dart',
      'test/api/beacon_admitted_helpers_hasura_test.dart',
    ];

    test('setUpAll calls loadJwtKeysForHasuraPgTests() with no overrides', () {
      final serverRoot = Directory.current.path;
      for (final relative in apiTestRelatives) {
        final src = File(p.join(serverRoot, relative)).readAsStringSync();
        final setUpAllStart = src.indexOf('setUpAll(() async {');
        expect(setUpAllStart, isNot(-1), reason: '$relative must declare setUpAll');
        final setUpAllEnd = src.indexOf('});', setUpAllStart);
        expect(setUpAllEnd, isNot(-1), reason: '$relative setUpAll block not found');
        final setUpAllBody = src.substring(setUpAllStart, setUpAllEnd);
        expect(
          setUpAllBody,
          contains('loadJwtKeysForHasuraPgTests()'),
          reason:
              '$relative setUpAll must call loadJwtKeysForHasuraPgTests() '
              'with default repo .env resolution (tentura-50o)',
        );
        expect(
          setUpAllBody,
          isNot(contains('_loadJwtKeysFromRepoDotEnv')),
          reason: '$relative setUpAll must not call private _loadJwtKeysFromRepoDotEnv',
        );
      }
    });

    for (final relative in apiTestRelatives) {
      test(
        '$relative subprocess: real setUpAll under fresh checkout does not emit JWT StateError',
        () async {
          final outcome = await _runFreshCheckoutDartTest([
            relative,
            '--reporter',
            'expanded',
          ]);
          for (final marker in _kHasuraJwtStateErrorMarkers) {
            expect(
              outcome.combined,
              isNot(contains(marker)),
              reason:
                  'setUpAll must not fail JWT load for fresh checkout '
                  '(exit ${outcome.exitCode}, output:\n${outcome.combined})',
            );
          }
          expect(
            outcome.exitCode,
            0,
            reason:
                'Hasura pg file must complete when JWT fallback is wired '
                '(output:\n${outcome.combined})',
          );
        },
        skip: hasuraPgHarnessSkip,
        timeout: const Timeout(Duration(minutes: 15)),
      );
    }
  });
}

bool get _isCiDartTestHost {
  final env = Platform.environment;
  return env['GITHUB_ACTIONS'] == 'true' ||
      env['CI'] == 'true' ||
      env['TEST_TARGET'] == 'server';
}

Future<({String stdout, String stderr, int exitCode, String combined})>
    _runFreshCheckoutDartTest(List<String> testArgs) async {
  final serverRoot = Directory.current.path;
  final repoRoot = p.normalize(p.join(serverRoot, '../..'));
  final dotEnv = File(p.join(repoRoot, '.env'));
  File? hiddenDotEnv;

  if (dotEnv.existsSync()) {
    hiddenDotEnv = File(
      '${dotEnv.path}.tentura50o_hide_${DateTime.timestamp().microsecondsSinceEpoch}',
    );
    await dotEnv.rename(hiddenDotEnv.path);
  }

  try {
    final env = Map<String, String>.from(Platform.environment)
      ..remove('JWT_PUBLIC_PEM')
      ..remove('JWT_PRIVATE_PEM');

    final ProcessResult result;
    if (_isCiDartTestHost) {
      // tentura-21x: do not nest run_with_test_cleanup.sh inside CI dart test.
      result = await Process.run(
        Platform.executable,
        ['test', ...testArgs],
        workingDirectory: serverRoot,
        environment: env,
      );
    } else {
      final script = p.normalize(
        p.join(serverRoot, '../../scripts/run_with_test_cleanup.sh'),
      );
      result = await Process.run(
        script,
        [
          '--timeout',
          '12m',
          '--',
          'dart',
          'test',
          ...testArgs,
        ],
        workingDirectory: serverRoot,
        environment: env,
      );
    }

    final stdout = '${result.stdout}';
    final stderr = '${result.stderr}';
    return (
      stdout: stdout,
      stderr: stderr,
      exitCode: result.exitCode,
      combined: '$stdout\n$stderr',
    );
  } finally {
    if (hiddenDotEnv != null && hiddenDotEnv.existsSync()) {
      await hiddenDotEnv.rename(dotEnv.path);
    }
  }
}
