import 'package:injectable/injectable.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logging/logging.dart';

import 'package:tentura/env.dart';

import 'service_base.dart';

@singleton
class FirebaseService extends ServiceBase {
  FirebaseService({
    required super.env,
    required super.logger,
  });

  @FactoryMethod(preResolve: true)
  static Future<FirebaseService> create({
    required Env env,
    required Logger logger,
  }) async {
    if (env.firebaseApiKey.isNotEmpty) {
      await Firebase.initializeApp(
        options: FirebaseOptions(
          appId: env.firebaseAppId,
          apiKey: env.firebaseApiKey,
          projectId: env.firebaseProjectId,
          authDomain: env.firebaseAuthDomain,
          storageBucket: env.firebaseStorageBucket,
          messagingSenderId: env.firebaseMessagingSenderId,
        ),
      );
    }
    return FirebaseService(
      env: env,
      logger: logger,
    );
  }
}
