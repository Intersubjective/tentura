import 'package:tentura/consts.dart';

/// Pure guard decision for `/accept-invite/:id` (testable without AutoRoute).
sealed class AcceptInviteGuardOutcome {}

final class AcceptInviteGuardAllow extends AcceptInviteGuardOutcome {}

/// Web: [goToLanding] returned true and the page is unloading.
final class AcceptInviteGuardLeaving extends AcceptInviteGuardOutcome {}

/// Native: redirect unauthenticated users to signup-with-invite.
final class AcceptInviteGuardSignup extends AcceptInviteGuardOutcome {
  AcceptInviteGuardSignup(this.code);

  final String code;

  String get signupPath => '$kPathSignUp/$code';
}

AcceptInviteGuardOutcome resolveAcceptInviteGuard({
  required bool isAuthenticated,
  required String code,
  required bool bouncedToLanding,
}) {
  if (isAuthenticated) {
    return AcceptInviteGuardAllow();
  }
  if (bouncedToLanding) {
    return AcceptInviteGuardLeaving();
  }
  return AcceptInviteGuardSignup(code);
}
