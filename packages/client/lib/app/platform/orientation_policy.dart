/// Platform-specific orientation policy (native vs web/PWA).
///
/// Design: `docs/tentura-design-system.md` (Orientation policy).
export 'orientation_policy_native.dart'
    if (dart.library.js_interop) 'orientation_policy_web.dart';
