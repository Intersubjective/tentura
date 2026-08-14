import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Forces [HomeScreen] compact chrome to rebuild on nested navigator
/// pop/remove — not only when [NavigationHistory] notifies.
///
/// auto_route's [StackRouter.onPopPage] calls [NavigationHistory.rebuildUrl]
/// only when [NavigationHistory.isRouteDataActive] is true for the popped
/// page. That predicate uses [RouteMatch.==] (including `children`), so a
/// detail whose match drifted from `urlState` (query/child updates) can pop
/// the page (list visible) without notifying history — leaving
/// `bottomNavigationBar: null` stuck. Browser back goes through
/// [RouterDelegate.setNewRoutePath] and restores chrome; in-app back does not.
///
/// Only pop/remove are observed: push already updates the URL (history
/// notifies), and reacting to didPush mid-build can schedule a rebuild loop.
class HomeShellChromeListenable extends ChangeNotifier {
  void tick() => notifyListeners();
}

/// Inherited by tab-branch [Navigator]s via AutoRoute's observer inheritance.
class HomeShellNavObserver extends NavigatorObserver {
  HomeShellNavObserver(this._chrome);

  final HomeShellChromeListenable _chrome;
  var _tickScheduled = false;

  /// Observer callbacks can run mid-build. Defer so [ListenableBuilder] is
  /// not marked dirty during build.
  void _bump() {
    if (_tickScheduled) return;
    _tickScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _tickScheduled = false;
      _chrome.tick();
    });
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _bump();

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _bump();
}
