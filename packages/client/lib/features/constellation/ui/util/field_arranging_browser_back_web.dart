import 'dart:js_interop';

import 'package:web/web.dart' as web;

import 'field_arranging_browser_back_sync.dart';

final _sync = FieldArrangingBrowserBackSync(
  pushState: () => web.window.history.pushState(
    ''.toJS,
    '',
    web.window.location.href,
  ),
  back: () => web.window.history.back(),
  replaceState: () => web.window.history.replaceState(
    ''.toJS,
    '',
    web.window.location.href,
  ),
);

var _listenerAttached = false;

void _onPopState(web.Event event) {
  _sync.onPopState();
}

void _ensureListener() {
  if (_listenerAttached) return;
  web.window.addEventListener('popstate', _onPopState.toJS);
  _listenerAttached = true;
}

void onFieldArrangingExitForNavigation() {
  _sync.onExitForNavigation();
}

/// Pushes a same-URL history entry while Arranging so the first browser Back
/// only exits the mode (#938 QA).
void syncFieldArrangingBrowserBackSentinel({
  required bool arranging,
  required void Function() onPopWhileArranging,
}) {
  if (arranging) {
    _ensureListener();
  }
  _sync.sync(
    arranging: arranging,
    onPopWhileArranging: onPopWhileArranging,
  );
}

void tearDownFieldArrangingBrowserBackForTest() {
  _sync.tearDown();
  if (_listenerAttached) {
    web.window.removeEventListener('popstate', _onPopState.toJS);
    _listenerAttached = false;
  }
}
