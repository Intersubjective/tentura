import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:web/web.dart' as web;

bool get isDesktopPlatform => false;
String get platformName => 'web';

/// Running as an installed web app (home-screen or desktop PWA), not in a
/// browser tab. Such a window has no address bar, so browser-chrome
/// instructions don't apply. iOS Safari also exposes `navigator.standalone`.
bool get isInstalledWebApp {
  try {
    if (web.window.matchMedia('(display-mode: standalone)').matches ||
        web.window.matchMedia('(display-mode: fullscreen)').matches ||
        web.window.matchMedia('(display-mode: minimal-ui)').matches ||
        web.window
            .matchMedia('(display-mode: window-controls-overlay)')
            .matches) {
      return true;
    }
    final standalone = (web.window.navigator as JSObject).getProperty(
      'standalone'.toJS,
    );
    return standalone != null &&
        standalone.isA<JSBoolean>() &&
        (standalone as JSBoolean).toDart;
  } catch (_) {
    return false;
  }
}
