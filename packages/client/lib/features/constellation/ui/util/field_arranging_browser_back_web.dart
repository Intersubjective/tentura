import 'dart:js_interop';

import 'package:web/web.dart' as web;

void Function()? _onPop;
var _sentinelPushed = false;
var _suppressNextPop = false;
var _listenerAttached = false;

void _onPopState(web.Event event) {
  if (_suppressNextPop) {
    _suppressNextPop = false;
    return;
  }
  if (_sentinelPushed) {
    _sentinelPushed = false;
    _onPop?.call();
  }
}

void _ensureListener() {
  if (_listenerAttached) return;
  web.window.addEventListener('popstate', _onPopState.toJS);
  _listenerAttached = true;
}

/// Pushes a same-URL history entry while Arranging so the first browser Back
/// only exits the mode (#938 QA).
void syncFieldArrangingBrowserBackSentinel({
  required bool arranging,
  required void Function() onPopWhileArranging,
}) {
  _onPop = onPopWhileArranging;
  if (arranging) {
    _ensureListener();
    if (!_sentinelPushed) {
      web.window.history.pushState(
        ''.toJS,
        '',
        web.window.location.href,
      );
      _sentinelPushed = true;
    }
    return;
  }
  if (_sentinelPushed) {
    _suppressNextPop = true;
    web.window.history.back();
    _sentinelPushed = false;
  }
}

void tearDownFieldArrangingBrowserBackForTest() {
  _onPop = null;
  _sentinelPushed = false;
  _suppressNextPop = false;
  if (_listenerAttached) {
    web.window.removeEventListener('popstate', _onPopState.toJS);
    _listenerAttached = false;
  }
}
