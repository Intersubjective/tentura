import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';

import 'seed_recovery_landing_url.dart';
import 'stale_session_redirect_policy.dart';

const _staleSessionReloadKey = 'tentura.staleSessionReload';

const _publicInviteFallback = '/invite/';

/// After a rejected browser session bootstrap, navigate to landing.
void reloadAfterRejectedSession({required bool clearAcknowledged}) {
  if (kQaIntegrationTestMode) {
    return;
  }
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
  stripStaleSeedRecoveryLandingEntry();
}

void clearStaleSessionBrowserGuard() {
  noteAuthenticatedBoot();
}

/// Post sign-out navigation: always `/invite/` (static landing).
///
/// `/` uses cookie-presence routing — a lingering session cookie would reload
/// WASM instead of the landing surface. `/invite/` is always landing HTML.
void redirectAfterSignOut({required bool clearAcknowledged}) {
  if (kQaIntegrationTestMode) {
    return;
  }
  web.window.location.assign(_publicInviteFallback);
}
