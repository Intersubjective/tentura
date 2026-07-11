import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/app/router/recover_route_guard.dart';
import 'package:tentura/app/router/root_router.gr.dart';

void main() {
  group('resolveRecoverAuthenticatedRedirect', () {
    test('returns HomeRoute when invite query is absent', () {
      expect(
        resolveRecoverAuthenticatedRedirect(),
        isA<HomeRoute>(),
      );
    });

    test('returns HomeRoute when invite query is invalid', () {
      expect(
        resolveRecoverAuthenticatedRedirect(inviteQuery: 'not-an-invite'),
        isA<HomeRoute>(),
      );
    });

    test('returns AcceptInviteRoute when invite query is valid', () {
      final route = resolveRecoverAuthenticatedRedirect(
        inviteQuery: 'I806d29daebbe',
      );
      expect(route, isA<AcceptInviteRoute>());
      expect(route!.rawPathParams['id'], 'I806d29daebbe');
    });
  });
}
