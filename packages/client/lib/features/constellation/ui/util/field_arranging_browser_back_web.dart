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
  if (_sync.onPopState()) {
    event.stopImmediatePropagation();
  }
}

/// Register before Flutter's router history listener. Window popstate
/// listeners run in registration order, including at-target capture listeners.
void installFieldArrangingBrowserBack() {
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
    installFieldArrangingBrowserBack();
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
