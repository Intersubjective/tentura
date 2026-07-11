import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';

import 'stale_session_redirect_policy.dart';

/// Replaces `/recover?…` landing entry URLs with the canonical app origin path
/// (`/#/…`), dropping funnel query params such as `auth_attempt_id`.
///
/// When [hashFragment] is omitted, strips only when the current hash already
/// points at an in-app route (post-recovery refresh). When provided (router
/// guard redirect), always strips and sets that hash.
void stripSeedRecoveryLandingEntry({String? hashFragment}) {
  if (kQaIntegrationTestMode) {
    return;
  }
  final loc = web.window.location;
  if (loc.pathname != '/recover') {
    return;
  }

  final hash = hashFragment ?? loc.hash;
  if (hashFragment == null) {
    if (isSeedRecoveryWasmEntry(pathname: loc.pathname, hash: hash)) {
      return;
    }
  }

  final normalizedHash = hash.isEmpty
      ? '#$kPathHome'
      : hash.startsWith('#')
      ? hash
      : '#$hash';
  web.window.history.replaceState(null, '', '/$normalizedHash');
}

/// Cleans a leftover `/recover?…` pathname after authenticated boot when the hash
/// already targets an in-app route.
void stripStaleSeedRecoveryLandingEntry() {
  stripSeedRecoveryLandingEntry();
}
