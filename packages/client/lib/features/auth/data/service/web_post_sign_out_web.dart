import 'web_rejected_session_redirect.dart';

/// After sign-out on web, send the user to the public landing surface.
void redirectToLandingAfterSignOut({bool clearAcknowledged = true}) {
  redirectAfterSignOut(clearAcknowledged: clearAcknowledged);
}
