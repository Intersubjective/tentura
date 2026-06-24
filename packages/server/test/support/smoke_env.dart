import 'package:injectable/injectable.dart';
import 'package:tentura_server/env.dart';

const _kSmokeOrigin = 'http://127.0.0.1:2080';

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
