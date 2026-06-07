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
  });
}
