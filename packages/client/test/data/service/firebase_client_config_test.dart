import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/data/service/firebase_client_config.dart';
import 'package:tentura/env.dart';

void main() {
  const validEnv = Env(
    firebaseApiKey: 'AIzaSyExampleKey',
    firebaseAppId: '1:123456789:web:abcdef123456',
    firebaseProjectId: 'tentura-dev',
    firebaseMessagingSenderId: '123456789',
  );

  test('accepts valid web app id', () {
    expect(isFirebaseClientConfigValid(validEnv), isTrue);
    expect(firebaseClientConfigIssue(validEnv), isNull);
  });

  test('rejects api key as app id', () {
    const env = Env(
      firebaseApiKey: 'AIzaSyExampleKey',
      firebaseAppId: 'AIzaSyExampleKey',
      firebaseProjectId: 'tentura-dev',
      firebaseMessagingSenderId: '123456789',
    );
    expect(isFirebaseClientConfigValid(env), isFalse);
    expect(
      firebaseClientConfigIssue(env),
      contains('FB_APP_ID looks like FB_API_KEY'),
    );
  });

  test('rejects empty app id when api key set', () {
    const env = Env(
      firebaseApiKey: 'AIzaSyExampleKey',
      firebaseAppId: '',
      firebaseProjectId: 'tentura-dev',
      firebaseMessagingSenderId: '123456789',
    );
    expect(isFirebaseClientConfigValid(env), isFalse);
    expect(firebaseClientConfigIssue(env), contains('FB_APP_ID is empty'));
  });
}
