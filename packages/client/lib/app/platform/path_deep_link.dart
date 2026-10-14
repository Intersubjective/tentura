// SPDX-License-Identifier: AGPL-3.0-only
import 'package:tentura/consts.dart';

export 'path_deep_link_stub.dart'
    if (dart.library.js_interop) 'path_deep_link_web.dart';

/// Detail paths that are handed out as plain path URLs (profile QR / share
/// link, request links) but that the web app only routes as hash routes.
const _pathDeepLinkPrefixes = [kPathProfileView, kPathBeaconView];

/// The hash-route URL (`/#/profile/view/U…`) to show instead of a path deep
/// link (`/profile/view/U…`), or `null` when [pathname] is not one or the
/// URL already carries a route in its fragment.
///
/// The server serves the app for any path, but the app routes on the
/// fragment, so `/profile/view/U…` used to open Home (`…/profile/view/U…#/home/work`).
String? hashUrlForPathDeepLink({
  required String pathname,
  String search = '',
  String hash = '',
}) {
  if (hash.isNotEmpty && hash != '#' && hash != '#/') {
    return null;
  }
  for (final prefix in _pathDeepLinkPrefixes) {
    if (pathname.length > prefix.length + 1 &&
        pathname.startsWith('$prefix/')) {
      return '/#$pathname$search';
    }
  }
  return null;
}
