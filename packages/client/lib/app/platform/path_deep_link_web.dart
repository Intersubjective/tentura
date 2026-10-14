// SPDX-License-Identifier: AGPL-3.0-only
import 'package:web/web.dart' as web;

import 'path_deep_link.dart' show hashUrlForPathDeepLink;

/// Rewrites a path deep link (`/profile/view/U…`) to its hash route before
/// the router reads the location, so shared links open the right screen.
void adoptPathDeepLink() {
  final location = web.window.location;
  final target = hashUrlForPathDeepLink(
    pathname: location.pathname,
    search: location.search,
    hash: location.hash,
  );
  if (target != null) {
    web.window.history.replaceState(null, '', target);
  }
}
