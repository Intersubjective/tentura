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
