import 'package:injectable/injectable.dart';
import 'package:postgres/postgres.dart';
import 'package:tentura_server/env.dart';

const _kSmokeOrigin = 'http://127.0.0.1:2080';

/// Whether [env]'s Postgres endpoint accepts connections (CI often has none).
Future<bool> smokePostgresReachable(Env env) async {
  try {
    final conn = await Connection.open(
      env.pgEndpoint,
      settings: env.pgEndpointSettings,
    ).timeout(const Duration(seconds: 2));
    await conn.close();
    return true;
  } catch (_) {
    return false;
  }
}

/// Hermetic prod [Env] for DI smoke tests — do not read `.env`.
Env smokeProdEnv() => Env(
      environment: Environment.prod,
      serverUri: Uri.parse(_kSmokeOrigin),
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      pgHost: '127.0.0.1',
      pgPort: 5432,
      pgPassword: 'password',
      kS3Endpoint: '127.0.0.1:9000',
      kS3AccessKey: 'minioadmin',
      kS3SecretKey: 'minioadmin',
      kS3Bucket: 'tentura',
      publicOrigin: _kSmokeOrigin,
      workersCount: 1,
      isDebugModeOn: true,
    );

/// Hermetic test [Env] with email auth explicitly disabled (ignores shell `.env`).
Env emailAuthUnconfiguredTestEnv() => Env(
      environment: Environment.test,
      resendApiKey: '',
      resendFromEmail: '',
      emailDebugSinkDir: '',
      qaAuthEnabled: false,
      qaAuthToken: '',
    );

/// Hermetic dev [Env] for DI smoke tests.
Env smokeDevEnv() => Env(
      environment: Environment.dev,
      serverUri: Uri.parse(_kSmokeOrigin),
      publicKey: Env.kJwtPublicKey,
      privateKey: Env.kJwtPrivateKey,
      pgHost: '127.0.0.1',
      pgPort: 5432,
      pgPassword: 'password',
      kS3Endpoint: '127.0.0.1:9000',
      kS3AccessKey: 'minioadmin',
      kS3SecretKey: 'minioadmin',
      kS3Bucket: 'tentura',
      publicOrigin: _kSmokeOrigin,
      workersCount: 1,
      isDebugModeOn: true,
    );
