import 'package:injectable/injectable.dart' show Environment;
import 'package:test/test.dart';

import 'package:tentura_server/data/service/oidc/google_oidc_service.dart';
import 'package:tentura_server/env.dart';

void main() {
  group('GoogleOidcService.buildGoogleAuthorizeUri', () {
    late GoogleOidcService service;

    setUp(() {
      service = GoogleOidcService(
        Env(
          environment: Environment.test,
          googleClientId: 'test-client-id.apps.googleusercontent.com',
          googleClientSecret: 'test-secret',
        ),
      );
    });

    test('includes prompt=select_account for account chooser', () {
      final uri = service.buildGoogleAuthorizeUri(
        redirectUri: 'https://app.example/api/auth/google/callback',
        state: 'state-token',
        codeChallenge: 'challenge',
        nonce: 'nonce-token',
      );

      expect(uri.queryParameters['prompt'], 'select_account');
      expect(uri.queryParameters['client_id'], 'test-client-id.apps.googleusercontent.com');
      expect(uri.queryParameters['redirect_uri'],
          'https://app.example/api/auth/google/callback');
    });
  });
}
