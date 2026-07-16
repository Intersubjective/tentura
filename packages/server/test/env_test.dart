import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/env.dart';

void main() {
  group('resolveServerEnvironment', () {
    test('enables dev only for an explicit dev value', () {
      expect(resolveServerEnvironment(Environment.dev), Environment.dev);
    });

    test('fails closed to prod for missing or unexpected values', () {
      expect(resolveServerEnvironment(null), Environment.prod);
      expect(resolveServerEnvironment(''), Environment.prod);
      expect(resolveServerEnvironment(Environment.prod), Environment.prod);
      expect(resolveServerEnvironment(Environment.test), Environment.prod);
      expect(resolveServerEnvironment('staging'), Environment.prod);
    });
  });

  group('resolveRealtimeActorEchoEnabled', () {
    test('defaults to actor-account convergence', () {
      expect(resolveRealtimeActorEchoEnabled(null), isTrue);
      expect(resolveRealtimeActorEchoEnabled(''), isTrue);
      expect(resolveRealtimeActorEchoEnabled('true'), isTrue);
    });

    test('only an explicit false activates compatibility filtering', () {
      expect(resolveRealtimeActorEchoEnabled('false'), isFalse);
      expect(resolveRealtimeActorEchoEnabled(' FALSE '), isFalse);
      expect(resolveRealtimeActorEchoEnabled('unexpected'), isTrue);
    });
  });

  group('resolveAttentionV1ShadowEnabled', () {
    test('defaults off and accepts only explicit true', () {
      expect(resolveAttentionV1ShadowEnabled(null), isFalse);
      expect(resolveAttentionV1ShadowEnabled('false'), isFalse);
      expect(resolveAttentionV1ShadowEnabled('unexpected'), isFalse);
      expect(resolveAttentionV1ShadowEnabled(' TRUE '), isTrue);
    });
  });

  group('isFcmConfigured', () {
    test('false when all three server creds are empty', () {
      final env = Env(
        fbProjectId: '',
        fbClientEmail: '',
        fbPrivateKey: '',
      );
      expect(env.isFcmConfigured, isFalse);
      expect(
        env.missingFcmServerCreds,
        ['FB_PROJECT_ID', 'FB_CLIENT_EMAIL', 'FB_PRIVATE_KEY'],
      );
    });

    test('true when all three server creds are set', () {
      final env = Env(
        fbProjectId: 'tentura-dev',
        fbClientEmail: 'firebase@tentura-dev.iam.gserviceaccount.com',
        fbPrivateKey:
            '-----BEGIN PRIVATE KEY-----\nkey\n-----END PRIVATE KEY-----',
      );
      expect(env.isFcmConfigured, isTrue);
      expect(env.missingFcmServerCreds, isEmpty);
    });

    test('false when only project id is set', () {
      final env = Env(
        fbProjectId: 'tentura-dev',
        fbClientEmail: '',
        fbPrivateKey: '',
      );
      expect(env.isFcmConfigured, isFalse);
      expect(
        env.missingFcmServerCreds,
        ['FB_CLIENT_EMAIL', 'FB_PRIVATE_KEY'],
      );
    });

    test('false when project id is whitespace only', () {
      final env = Env(
        fbProjectId: '   ',
        fbClientEmail: 'e@example.com',
        fbPrivateKey: 'key',
      );
      expect(env.isFcmConfigured, isFalse);
      expect(env.missingFcmServerCreds, ['FB_PROJECT_ID']);
    });
  });
}
