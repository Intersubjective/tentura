import 'package:web/web.dart' as web;

import 'stale_session_redirect_policy.dart';

const _staleSessionReloadKey = 'tentura.staleSessionReload';

const _publicInviteFallback = '/invite/';

/// After a rejected browser session bootstrap, navigate to landing.
void reloadAfterRejectedSession({required bool clearAcknowledged}) {
  if (!shouldBounceRejectedSessionToLanding(
    pathname: web.window.location.pathname,
    hash: web.window.location.hash,
  )) {
    return;
  }
  if (!clearAcknowledged) {
    web.window.location.replace(_publicInviteFallback);
    return;
  }
  if (web.window.sessionStorage.getItem(_staleSessionReloadKey) != null) {
    web.window.sessionStorage.removeItem(_staleSessionReloadKey);
    web.window.location.replace(_publicInviteFallback);
    return;
  }
  web.window.sessionStorage.setItem(_staleSessionReloadKey, '1');
  web.window.location.replace('/');
}

/// Clears the per-tab stale-session guard after a successful authenticated boot.
void noteAuthenticatedBoot() {
  web.window.sessionStorage.removeItem(_staleSessionReloadKey);
}

/// Post sign-out navigation: `/` when cookie clear acknowledged, else `/invite/`.
void redirectAfterSignOut({required bool clearAcknowledged}) {
  web.window.location.assign(clearAcknowledged ? '/' : _publicInviteFallback);
}
