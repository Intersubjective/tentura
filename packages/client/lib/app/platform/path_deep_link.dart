// SPDX-License-Identifier: AGPL-3.0-only
// Selects the platform implementation of [adoptPathDeepLink]; the URL policy
// lives in path_deep_link_policy.dart.
export 'path_deep_link_stub.dart'
    if (dart.library.js_interop) 'path_deep_link_web.dart';
