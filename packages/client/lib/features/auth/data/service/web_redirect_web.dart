import 'package:web/web.dart' as web;

import 'package:tentura/consts.dart';

/// Sends the browser to the static landing host (`tentura.io` / `dev.tentura.io`).
///
/// The WASM app has no login UI: unauthenticated web users are bounced to the
/// landing, which owns signup + invite previews. [invitePath] (e.g.
/// `/invite/I…`) targets a specific landing page; otherwise the landing root.
///
/// Returns `true` so the caller knows a top-level navigation was triggered
/// (the page unloads immediately after).
bool goToLanding({String? invitePath}) {
  final base = Uri.parse(
    resolveInviteLinkHost(
      inviteLinkHost: kInviteLinkHost,
      serverName: kServerName,
    ),
  );
  final target = base.replace(
    path: invitePath ?? '/',
    queryParameters: const <String, String>{},
    fragment: '',
  );
  web.window.location.assign(target.toString());
  return true;
}
