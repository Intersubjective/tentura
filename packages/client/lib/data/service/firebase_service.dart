import 'package:injectable/injectable.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:logging/logging.dart';

import 'package:tentura/app/boot_step.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/notification/fcm_debug_log.dart';

import 'firebase_client_config.dart';
import 'service_base.dart';

@singleton
class FirebaseService extends ServiceBase {
  FirebaseService({
    required super.env,
    required super.logger,
    this.isInitialized = false,
  });

  /// Whether the Firebase app is up. False when the config is missing, or
  /// when initialisation failed or hung at startup (#878): push is not
  /// essential, so startup goes on without it.
  final bool isInitialized;

  @FactoryMethod(preResolve: true)
  static Future<FirebaseService> create({
    required Env env,
    required Logger logger,
    @ignoreParam Future<void> Function(FirebaseOptions options)? initializeApp,
    @ignoreParam Duration initTimeout = kFirebaseInitTimeout,
  }) async {
    logFirebaseClientConfig(env);
    var isInitialized = false;
    if (isFirebaseClientConfigValid(env)) {
      fcmLog('FirebaseService: initializing Firebase app');
      final options = FirebaseOptions(
        appId: env.firebaseAppId,
        apiKey: env.firebaseApiKey,
        projectId: env.firebaseProjectId,
        authDomain: env.firebaseAuthDomain,
        storageBucket: env.firebaseStorageBucket,
        messagingSenderId: env.firebaseMessagingSenderId,
      );
      try {
        // Web: firebase_core_web loads the Firebase JS SDK with a dynamic
        // import(); when that import fails (blocked or unreachable host) the
        // init never completes, which held startup until its 60 s timeout
        // (#878, TENTURA-CLIENT-5J).
        await bootStep(
          'firebase_init',
          () => (initializeApp ?? _initializeApp)(options).timeout(initTimeout),
        );
        isInitialized = true;
        fcmLog('FirebaseService: Firebase.initializeApp OK');
      } on Object catch (e, st) {
        logger.warning(
          'Firebase init failed; starting without push notifications',
          e,
          st,
        );
        fcmLog('FirebaseService: Firebase.initializeApp failed: $e');
      }
    } else {
      fcmLog(
        'FirebaseService: skip init '
        '(${firebaseClientConfigIssue(env) ?? 'FB_API_KEY empty'})',
      );
    }
    return FirebaseService(
      env: env,
      logger: logger,
      isInitialized: isInitialized,
    );
  }

  static Future<void> _initializeApp(FirebaseOptions options) =>
      Firebase.initializeApp(options: options);
}

/// Longest the startup waits for Firebase before going on without it (#878).
const kFirebaseInitTimeout = Duration(seconds: 15);
