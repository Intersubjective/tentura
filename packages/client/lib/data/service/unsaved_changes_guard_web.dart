import 'dart:js_interop';

import 'package:web/web.dart' as web;

final _dirtyOwners = <Object>{};
var _listenerAttached = false;

void _onBeforeUnload(web.Event event) {
  if (_dirtyOwners.isEmpty) return;
  event.preventDefault();
  (event as web.BeforeUnloadEvent).returnValue = '';
}

void unsavedChangesGuardSetDirty(Object owner, bool dirty) {
  if (dirty) {
    _dirtyOwners.add(owner);
    if (!_listenerAttached) {
      web.window.addEventListener('beforeunload', _onBeforeUnload.toJS);
      _listenerAttached = true;
    }
    return;
  }
  _dirtyOwners.remove(owner);
  if (_dirtyOwners.isEmpty && _listenerAttached) {
    web.window.removeEventListener('beforeunload', _onBeforeUnload.toJS);
    _listenerAttached = false;
  }
}

void unsavedChangesGuardResetForTest() {
  _dirtyOwners.clear();
  if (_listenerAttached) {
    web.window.removeEventListener('beforeunload', _onBeforeUnload.toJS);
    _listenerAttached = false;
  }
}
