import 'package:test/test.dart';

import 'package:tentura_server/api/http/oauth_return_uri.dart';

void main() {
  const origin = 'https://dev.lvh.me:9443';

  group('sanitizeOAuthReturnTo', () {
    test('accepts same-origin relative invite path', () {
      expect(
        sanitizeOAuthReturnTo(
          raw: '/invite/Iabc123',
          publicOrigin: origin,
        ),
        'https://dev.lvh.me:9443/invite/Iabc123',
      );
    });

    test('accepts same-origin absolute URL', () {
      expect(
        sanitizeOAuthReturnTo(
          raw: 'https://dev.lvh.me:9443/invite/Iabc123',
          publicOrigin: origin,
        ),
        'https://dev.lvh.me:9443/invite/Iabc123',
      );
    });

    test('rejects external origin', () {
      expect(
        sanitizeOAuthReturnTo(
          raw: 'https://evil.example/invite/Iabc123',
          publicOrigin: origin,
        ),
        '',
      );
    });

    test('rejects scheme-less non-path values', () {
      expect(
        sanitizeOAuthReturnTo(raw: 'invite/Iabc123', publicOrigin: origin),
        '',
      );
    });
  });

  group('destinationAfterOAuthCallback', () {
    test('appends signed_in for invite return', () {
      expect(
        destinationAfterOAuthCallback(
          returnTo: 'https://dev.lvh.me:9443/invite/Iabc123',
          publicOrigin: origin,
        ),
        'https://dev.lvh.me:9443/invite/Iabc123?signed_in=1',
      );
    });

    test('defaults to public origin when returnTo empty', () {
      expect(
        destinationAfterOAuthCallback(returnTo: '', publicOrigin: origin),
        '$origin/',
      );
    });

    test('appends new=1 for invite return when account is new', () {
      expect(
        destinationAfterOAuthCallback(
          returnTo: 'https://dev.lvh.me:9443/invite/Iabc123',
          publicOrigin: origin,
          isNewAccount: true,
        ),
        'https://dev.lvh.me:9443/invite/Iabc123?signed_in=1&new=1',
      );
    });

    test('new account with empty returnTo lands on landing /invite/', () {
      // Not `/`: with a fresh session cookie the root routes into WASM
      // (ADR 0002); `/invite/` always serves the landing post-signup flow.
      expect(
        destinationAfterOAuthCallback(
          returnTo: '',
          publicOrigin: origin,
          isNewAccount: true,
        ),
        '$origin/invite/?signed_in=1&new=1',
      );
    });

    test('login (not new) keeps redirect without new=1', () {
      expect(
        destinationAfterOAuthCallback(
          returnTo: 'https://dev.lvh.me:9443/invite/Iabc123',
          publicOrigin: origin,
          isNewAccount: false,
        ),
        'https://dev.lvh.me:9443/invite/Iabc123?signed_in=1',
      );
    });
  });
}
