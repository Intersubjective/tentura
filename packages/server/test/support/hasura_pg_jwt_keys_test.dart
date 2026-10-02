// Hasura pg harness JWT keys must load without repo `.env` or process JWT_*
// env vars (fresh checkout / worktree).

import 'dart:io';

import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:test/test.dart';
import 'package:tentura_server/env.dart';

import 'hasura_pg_jwt_keys.dart';

const _markerPublic =
    r'-----BEGIN PUBLIC KEY-----\nMCowBQYDK2VwAyEA2CmIb3Ho2eb6m8WIog6KiyzCY05sbyX04PiGlH5baDw=\n-----END PUBLIC KEY-----';
const _markerPrivate =
    r'-----BEGIN PRIVATE KEY-----\nMC4CAQAwBQYDK2VwBCIEIN3rCo3wCksyxX4qBYAC1vFr51kx/Od78QVrRLOV1orF\n-----END PRIVATE KEY-----';

void main() {
  group('loadJwtKeysForHasuraPgTests override hooks', () {
    test(
      'uses embedded test keys when repo .env is missing and JWT env is empty',
      () {
        final keys = loadJwtKeysForHasuraPgTests(
          repoDotEnvOverride: File(
            '${Directory.systemTemp.path}/missing-tentura-env-${DateTime.timestamp().microsecondsSinceEpoch}',
          ),
          platformEnvironmentOverride: const {},
        );

        final expectedPublic = Env.kJwtPublicKey.replaceAll(r'\n', '\n');
        final expectedPrivate = Env.kJwtPrivateKey.replaceAll(r'\n', '\n');

        expect(keys.publicKey.replaceAll(r'\n', '\n'), equals(expectedPublic));
        expect(
          keys.privateKey.replaceAll(r'\n', '\n'),
          equals(expectedPrivate),
        );
        expect(EdDSAPublicKey.fromPEM(keys.publicKey).bytes, isNotEmpty);
        expect(EdDSAPrivateKey.fromPEM(keys.privateKey).seed, isNotEmpty);
      },
    );

    test(
      'uses process JWT env when repo .env is missing and platformEnvironmentOverride supplies PEMs',
      () {
        final keys = loadJwtKeysForHasuraPgTests(
          repoDotEnvOverride: File(
            '${Directory.systemTemp.path}/missing-tentura-env-${DateTime.timestamp().microsecondsSinceEpoch}',
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

    test(
      'uses embedded test keys when repo .env exists but omits JWT PEM entries',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'tentura-hasura-jwt-',
        );
        addTearDown(() => dir.delete(recursive: true));
        final dotEnv = File('${dir.path}/.env');
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
      },
    );

    test('prefers JWT PEM values from repo .env when present', () async {
      final dir = await Directory.systemTemp.createTemp('tentura-hasura-jwt-');
      addTearDown(() => dir.delete(recursive: true));
      final dotEnv = File('${dir.path}/.env');
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
}
