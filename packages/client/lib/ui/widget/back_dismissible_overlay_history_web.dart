import 'dart:async';

import 'package:web/web.dart' as web;

class BackDismissibleOverlayHistorySentinel {
  BackDismissibleOverlayHistorySentinel({required void Function() onPop}) {
    _active = true;
    web.window.history.pushState(null, '', web.window.location.href);
    _popStateSub = web.window.onPopState.listen((_) {
      if (!_active) return;
      _active = false;
      onPop();
    });
  }

  // Owned by this sentinel and cancelled in dispose().
  // ignore: cancel_subscriptions
  StreamSubscription<web.PopStateEvent>? _popStateSub;
  var _active = false;

  void markHandledByBack() {
    _active = false;
  }

  void dispose() {
    final sub = _popStateSub;
    _popStateSub = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    if (!_active) return;
    _active = false;
    web.window.history.back();
  }
}
