import 'web_redirect_web.dart';

/// After sign-out on web, send the user to the landing (no in-app login UI).
void redirectToLandingAfterSignOut() {
  goToLanding();
}
