import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/firebase_service.dart';
import 'package:tentura/env.dart';

void main() {
  // A config valid enough for FirebaseService to initialise Firebase.
  const env = Env(
    firebaseApiKey: 'AIzaSyExampleKey',
    firebaseAppId: '1:123456789:web:abcdef123456',
    firebaseProjectId: 'tentura-dev',
    firebaseMessagingSenderId: '123456789',
  );

  late Logger logger;
  late List<LogRecord> warnings;

  setUp(() {
    logger = Logger.detached('FirebaseServiceTest')..level = Level.ALL;
    warnings = [];
    logger.onRecord.where((r) => r.level >= Level.WARNING).listen(warnings.add);
  });

  // #878: on web, firebase_core_web loads the Firebase JS SDK with a dynamic
  // import() whose failure never completes Firebase.initializeApp. Startup
  // waited for it and failed after 60 s (TENTURA-CLIENT-5J). Push is not
  // essential: startup goes on without Firebase.
  test('a Firebase init that never finishes does not block startup', () async {
    final service = await FirebaseService.create(
      env: env,
      logger: logger,
      initializeApp: (_) => Completer<void>().future,
      initTimeout: const Duration(milliseconds: 10),
    );

    expect(service.isInitialized, isFalse);
    expect(warnings, isNotEmpty);
  });

  test('a Firebase init error does not fail startup', () async {
    final service = await FirebaseService.create(
      env: env,
      logger: logger,
      initializeApp: (_) async => throw Exception('import() failed'),
    );

    expect(service.isInitialized, isFalse);
    expect(warnings, isNotEmpty);
  });

  // #880: blocked gstatic Firebase JS import must not wait for initializeApp
  // or the 15 s init timeout.
  test(
    'a blocked Firebase web SDK import skips initializeApp immediately',
    () async {
      var initializeAppCalled = false;
      final stopwatch = Stopwatch()..start();
      final service = await FirebaseService.create(
        env: env,
        logger: logger,
        assertWebSdkReachable: () async => throw StateError(
          'TypeError: Failed to fetch dynamically imported module: '
          'https://www.gstatic.com/firebasejs/12.17.0/firebase-app.js',
        ),
      initializeApp: (_) async {
        initializeAppCalled = true;
      },
    );
      stopwatch.stop();

      expect(initializeAppCalled, isFalse);
      expect(service.isInitialized, isFalse);
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
      expect(warnings, isNotEmpty);
    },
  );

  test('a Firebase init that finishes marks the service initialised', () async {
    FirebaseOptions? used;
    final service = await FirebaseService.create(
      env: env,
      logger: logger,
      initializeApp: (options) async => used = options,
    );

    expect(service.isInitialized, isTrue);
    expect(used?.projectId, 'tentura-dev');
    expect(warnings, isEmpty);
  });
}
