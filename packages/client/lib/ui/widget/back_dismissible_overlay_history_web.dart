import 'dart:async';

import 'package:web/web.dart' as web;

class BackDismissibleOverlayHistorySentinel {
  BackDismissibleOverlayHistorySentinel({required void Function() onPop}) {
    _active = true;
    _stack.add(this);
    web.window.history.pushState(null, '', web.window.location.href);
    _popStateSub = web.window.onPopState.listen((event) {
      if (!_active) return;
      if (identical(_consumedPopStateEvent, event)) return;
      if (_consumeSyntheticPopStateEvent(event)) return;
      if (_stack.isEmpty || !identical(_stack.last, this)) return;
      _active = false;
      _stack.remove(this);
      _markPopStateEventConsumed(event);
      onPop();
    });
  }

  // Same-URL history sentinels can be nested (room surface -> photo viewer).
  // The browser sends one popstate to every listener, so only the top sentinel
  // may consume it; otherwise one Back closes both the child and parent overlay.
  static final List<BackDismissibleOverlayHistorySentinel> _stack = [];
  static web.PopStateEvent? _consumedPopStateEvent;

  // Programmatic overlay closes call history.back() to remove their own dummy
  // entry.  When a parent sentinel remains below, that generated popstate must
  // be swallowed instead of closing the parent overlay too.
  static int _syntheticPopStatesToConsume = 0;

  // Owned by this sentinel and cancelled in dispose().
  // ignore: cancel_subscriptions
  StreamSubscription<web.PopStateEvent>? _popStateSub;
  var _active = false;

  void markHandledByBack() {
    _active = false;
    _stack.remove(this);
  }

  void dispose({bool consumeGeneratedPop = false}) {
    final sub = _popStateSub;
    _popStateSub = null;
    if (sub != null) {
      unawaited(sub.cancel());
    }
    _stack.remove(this);
    if (!_active) return;
    _active = false;
    if (consumeGeneratedPop && _stack.isNotEmpty) {
      _syntheticPopStatesToConsume += 1;
    }
    web.window.history.back();
  }

  static bool _consumeSyntheticPopStateEvent(web.PopStateEvent event) {
    if (_syntheticPopStatesToConsume == 0) {
      return false;
    }
    _syntheticPopStatesToConsume -= 1;
    _markPopStateEventConsumed(event);
    return true;
  }

  static void _markPopStateEventConsumed(web.PopStateEvent event) {
    _consumedPopStateEvent = event;
    scheduleMicrotask(() {
      if (identical(_consumedPopStateEvent, event)) {
        _consumedPopStateEvent = null;
      }
    });
  }
}
