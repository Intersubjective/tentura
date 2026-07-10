import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';

/// Sends the browser to the static landing on the public origin (`tentura.io` / `dev.tentura.io`).
///
/// The WASM app has no login UI: unauthenticated web users are bounced to the
/// landing, which owns signup + invite previews. [invitePath] (e.g.
/// `/invite/I…`) targets a specific landing page; otherwise the landing root.
///
/// Returns `true` so the caller knows a top-level navigation was triggered
/// (the page unloads immediately after).
bool goToLanding({String? invitePath}) {
  if (kQaDisableWebRedirects) {
    return false;
  }
  final target = Uri.parse(kServerName).replace(
    path: invitePath ?? '/invite/',
    queryParameters: const <String, String>{},
    fragment: '',
  );
  web.window.location.assign(target.toString());
  return true;
}
