import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'package:tentura/app/router/home_tab_branches.dart';
import 'package:tentura/features/home/ui/widget/home_tab_transition_listener.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// One-shot snackbar after a hash URL falls back through the `*` redirect (#1106).
final class UnknownHashRouteNotice {
  UnknownHashRouteNotice._();

  static final instance = UnknownHashRouteNotice._();

  var _pending = false;
  var _shownThisSession = false;
  final _scheduleListeners = <VoidCallback>{};

  bool get hasPending => _pending && !_shownThisSession;

  /// Notified when [schedule] sets a new pending notice (cold-start race /
  /// in-app wildcard while already on Requests).
  void addScheduleListener(VoidCallback listener) {
    _scheduleListeners.add(listener);
  }

  void removeScheduleListener(VoidCallback listener) {
    _scheduleListeners.remove(listener);
  }

  void schedule() {
    if (_shownThisSession) return;
    final wasPending = _pending;
    _pending = true;
    if (!wasPending) {
      for (final listener in _scheduleListeners.toList()) {
        listener();
      }
    }
  }

  bool takePending() {
    if (!_pending || _shownThisSession) return false;
    _pending = false;
    _shownThisSession = true;
    return true;
  }

  void resetForTest() {
    _pending = false;
    _shownThisSession = false;
  }
}

/// Shows [L10n.unknownHashRouteSnackBar] once on the Requests tab after a
/// wildcard fallback.
class UnknownHashRouteNoticeListener extends StatefulWidget {
  const UnknownHashRouteNoticeListener({
    required this.tabsRouter,
    required this.child,
    super.key,
  });

  final TabsRouter tabsRouter;
  final Widget child;

  @override
  State<UnknownHashRouteNoticeListener> createState() =>
      _UnknownHashRouteNoticeListenerState();
}

class _UnknownHashRouteNoticeListenerState
    extends State<UnknownHashRouteNoticeListener> {
  int get _workTabIndex => HomeTabSpec.forTab(HomeTab.work).index;

  var _showQueued = false;

  @override
  void initState() {
    super.initState();
    UnknownHashRouteNotice.instance.addScheduleListener(
      _onNoticeScheduled,
    );
    widget.tabsRouter.addListener(_onTabsRouterUpdated);
    if (UnknownHashRouteNotice.instance.hasPending) {
      unawaited(_queueShowOnWorkTab());
    }
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_queueShowOnWorkTab());
      }
    });
  }

  @override
  void dispose() {
    UnknownHashRouteNotice.instance.removeScheduleListener(
      _onNoticeScheduled,
    );
    widget.tabsRouter.removeListener(_onTabsRouterUpdated);
    super.dispose();
  }

  void _onNoticeScheduled() => unawaited(_queueShowOnWorkTab());

  void _onTabsRouterUpdated() {
    if (widget.tabsRouter.activeIndex == _workTabIndex) {
      unawaited(_queueShowOnWorkTab());
    }
  }

  /// Survives [ClearSnackBarsOnPushObserver] on the Home initial push (#1106).
  Future<void> _queueShowOnWorkTab() async {
    if (!UnknownHashRouteNotice.instance.hasPending) return;
    if (_showQueued) return;
    _showQueued = true;
    try {
      await SchedulerBinding.instance.endOfFrame;
      await SchedulerBinding.instance.endOfFrame;
      if (!mounted) return;
      if (widget.tabsRouter.activeIndex != _workTabIndex) return;
      await _showAfterNavigationClears();
    } finally {
      _showQueued = false;
    }
  }

  /// [ClearSnackBarsOnPushObserver] clears in a microtask on didPush (#1106).
  Future<void> _showAfterNavigationClears() async {
    final completer = Completer<void>();
    scheduleMicrotask(() {
      scheduleMicrotask(() {
        if (!completer.isCompleted) completer.complete();
      });
    });
    await completer.future;
    if (!mounted) return;
    _maybeShowSnackBar(context);
  }

  void _maybeShowSnackBar(BuildContext context) {
    if (!UnknownHashRouteNotice.instance.hasPending) return;
    final l10n = L10n.of(context);
    if (l10n == null) return;
    if (snackbarKey.currentState == null) return;
    if (!UnknownHashRouteNotice.instance.takePending()) return;
    showSnackBar(context, text: l10n.unknownHashRouteSnackBar);
  }

  @override
  Widget build(BuildContext context) {
    return HomeTabTransitionListener(
      tabsRouter: widget.tabsRouter,
      tab: HomeTab.work,
      onEnter: () => unawaited(_queueShowOnWorkTab()),
      child: widget.child,
    );
  }
}
