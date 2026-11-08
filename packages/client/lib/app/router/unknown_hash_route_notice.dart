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

  bool get hasPending => _pending && !_shownThisSession;

  void schedule() {
    if (_shownThisSession) return;
    _pending = true;
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

  @override
  void initState() {
    super.initState();
    if (widget.tabsRouter.activeIndex == _workTabIndex) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _maybeShowSnackBar(context);
        }
      });
    }
  }

  void _maybeShowSnackBar(BuildContext context) {
    if (!UnknownHashRouteNotice.instance.hasPending) return;
    if (snackbarKey.currentState == null) return;
    if (!UnknownHashRouteNotice.instance.takePending()) return;
    final l10n = L10n.of(context);
    if (l10n == null) return;
    showSnackBar(context, text: l10n.unknownHashRouteSnackBar);
  }

  @override
  Widget build(BuildContext context) {
    return HomeTabTransitionListener(
      tabsRouter: widget.tabsRouter,
      tab: HomeTab.work,
      onEnter: () => _maybeShowSnackBar(context),
      child: widget.child,
    );
  }
}
