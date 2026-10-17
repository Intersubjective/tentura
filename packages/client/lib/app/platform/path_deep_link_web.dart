// SPDX-License-Identifier: AGPL-3.0-only
import 'package:web/web.dart' as web;

import 'path_deep_link_policy.dart';

/// Rewrites a path deep link (`/profile/view/U…`) to its hash route before
/// the engine and router read the location, so shared links open the right
/// screen. Called first thing in `main()`, before the binding is initialised.
void adoptPathDeepLink() {
  final location = web.window.location;
  final target = hashUrlForPathDeepLink(
    pathname: location.pathname,
    search: location.search,
    hash: location.hash,
  );
  if (target != null) {
    // Keep the current history state so an engine tag (if already written)
    // survives the rewrite.
    web.window.history.replaceState(web.window.history.state, '', target);
  }
}
