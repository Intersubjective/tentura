import 'package:test/test.dart';

import 'package:tentura_server/api/http/auth_invite_required_page.dart';

void main() {
  const origin = 'https://dev.tentura.io';

  group('publicLandingUrl', () {
    test('ensures trailing slash', () {
      expect(publicLandingUrl(origin), '$origin/');
      expect(publicLandingUrl('$origin/'), '$origin/');
    });
  });

  group('invitePageUrlFromReturnTo', () {
    test('parses relative invite path', () {
      expect(
        invitePageUrlFromReturnTo(
          returnTo: '/invite/Iabc123',
          publicOrigin: origin,
        ),
        '$origin/invite/Iabc123',
      );
    });

    test('parses absolute invite URL', () {
      expect(
        invitePageUrlFromReturnTo(
          returnTo: '$origin/invite/Iabc123',
          publicOrigin: origin,
        ),
        '$origin/invite/Iabc123',
      );
    });

    test('returns null for non-invite return', () {
      expect(
        invitePageUrlFromReturnTo(returnTo: '/', publicOrigin: origin),
        isNull,
      );
    });
  });

  group('renderAuthInviteRequiredPage', () {
    test('includes landing CTA and recovery copy', () {
      final html = renderAuthInviteRequiredPage(
        landingUrl: '$origin/',
      );
      expect(html, contains('No account found for this sign-in'));
      expect(html, contains('href="$origin/"'));
      expect(html, contains('Back to sign in'));
      expect(html, contains('invite link or code'));
    });

    test('includes optional invite return CTA', () {
      final html = renderAuthInviteRequiredPage(
        landingUrl: '$origin/',
        inviteUrl: '$origin/invite/Iabc123',
      );
      expect(html, contains('Return to your invite'));
      expect(html, contains('href="$origin/invite/Iabc123"'));
    });
  });
}
