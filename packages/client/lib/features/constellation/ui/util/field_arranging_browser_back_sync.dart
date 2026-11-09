/// Testable browser-history behaviour for Field Arranging (#938 / #1062).
///
/// Web wires [FieldArrangingBrowserBackSync] to `history.pushState` / `back`;
/// VM tests use a fake port.
class FieldArrangingBrowserBackSync {
  FieldArrangingBrowserBackSync({
    required void Function() this._pushState,
    required void Function() this._back,
    required void Function() this._replaceState,
  });

  final void Function() _pushState;
  final void Function() _back;
  final void Function() _replaceState;

  void Function()? _onPop;
  var _sentinelPushed = false;
  var _suppressNextPop = false;
  var _dropWithoutTraverseOnRelease = false;

  int backInvocationCount = 0;
  int replaceStateInvocationCount = 0;

  bool get sentinelPushed => _sentinelPushed;

  void onPopState() {
    if (_suppressNextPop) {
      _suppressNextPop = false;
      return;
    }
    if (_sentinelPushed) {
      _sentinelPushed = false;
      _onPop?.call();
    }
  }

  void onExitForNavigation() {
    _dropWithoutTraverseOnRelease = true;
  }

  void sync({
    required bool arranging,
    required void Function() onPopWhileArranging,
  }) {
    _onPop = onPopWhileArranging;
    if (arranging) {
      if (!_sentinelPushed) {
        _pushState();
        _sentinelPushed = true;
      }
      return;
    }
    if (!_sentinelPushed) {
      return;
    }
    if (_dropWithoutTraverseOnRelease) {
      _dropWithoutTraverseOnRelease = false;
      _replaceState();
      replaceStateInvocationCount++;
      _sentinelPushed = false;
      return;
    }
    _suppressNextPop = true;
    _back();
    backInvocationCount++;
    _sentinelPushed = false;
  }

  void tearDown() {
    _onPop = null;
    _sentinelPushed = false;
    _suppressNextPop = false;
    _dropWithoutTraverseOnRelease = false;
    backInvocationCount = 0;
    replaceStateInvocationCount = 0;
  }
}
