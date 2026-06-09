import 'package:web/web.dart' as web;

import 'stale_session_redirect_policy.dart';

/// Seed recovery is explicit — do not auto-sign-in from cookie or stale local id.
bool get skipSessionCookieBootstrap => isSeedRecoveryWasmEntry(
  pathname: web.window.location.pathname,
  hash: web.window.location.hash,
);
