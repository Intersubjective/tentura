import 'package:test/test.dart';
import 'package:tentura/app/router/accept_invite_guard.dart';
import 'package:tentura/consts.dart';

void main() {
  group('resolveAcceptInviteGuard', () {
    test('authenticated allows the accept screen', () {
      expect(
        resolveAcceptInviteGuard(
          isAuthenticated: true,
          code: 'Iabc',
          bouncedToLanding: false,
        ),
        isA<AcceptInviteGuardAllow>(),
      );
    });

    test('web anon with landing bounce leaves the app', () {
      expect(
        resolveAcceptInviteGuard(
          isAuthenticated: false,
          code: 'Iabc',
          bouncedToLanding: true,
        ),
        isA<AcceptInviteGuardLeaving>(),
      );
    });

    test('native anon redirects to signup-with-invite', () {
      final outcome = resolveAcceptInviteGuard(
        isAuthenticated: false,
        code: 'Iabc',
        bouncedToLanding: false,
      );
      expect(outcome, isA<AcceptInviteGuardSignup>());
      expect(
        (outcome as AcceptInviteGuardSignup).signupPath,
        '$kPathSignUp/Iabc',
      );
    });
  });
}
