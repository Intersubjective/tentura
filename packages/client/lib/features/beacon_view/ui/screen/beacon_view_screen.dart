import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/coordination_room_navigation.dart';
import 'package:tentura/features/beacon_threads/ui/widget/thread_detail.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_navigation_scope.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../widget/beacon_activity_sheet.dart';
import '../widget/beacon_anchor_status.dart';
import '../widget/beacon_now_surface.dart';
import '../widget/beacon_people_surface.dart';
import '../widget/beacon_room_surface.dart';
import '../widget/beacon_surface_tabs.dart';
import '../widget/beacon_view_app_bar_overflow.dart';
import '../widget/beacon_view_app_bar_title.dart';
import '../widget/beacon_view_status_bottom_sheet.dart';
import '../widget/beacon_view_constants.dart';

bool _beaconPeopleTabAttentionQueryTruthy(String? v) {
  if (v == null || v.isEmpty) return false;
  final s = v.toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

/// Query [kQueryBeaconViewTab] → [BeaconSurface].
BeaconSurface _beaconViewSurface(String? viewTab) {
  switch (viewTab) {
    case kBeaconViewTabNow:
      return BeaconSurface.now;
    case 'people':
      return BeaconSurface.people;
    case 'log':
      return BeaconSurface.now;
    case kBeaconViewTabThreads:
      return BeaconSurface.room;
    default:
      return BeaconSurface.now;
  }
}

String _beaconSurfaceViewTab(BeaconSurface surface) => switch (surface) {
  BeaconSurface.now => kBeaconViewTabNow,
  BeaconSurface.room => kBeaconViewTabThreads,
  BeaconSurface.people => 'people',
};

/// Expanded thread split when the list has rows — not gated on room navigation.
bool beaconViewUsesExpandedThreadSplit({
  required WindowClass windowClass,
  required bool showBeaconContent,
  required bool hasThreadRows,
}) => windowClass == WindowClass.expanded && showBeaconContent && hasThreadRows;

/// Ideal / clamped width for the room (3rd) pane in an ops|room split.
///
/// Pass [preferredWidth] to honor a user drag override; otherwise uses
/// 42% of [availableWidth] capped by [TenturaTokens.chatColumnMaxWidth].
/// Always leaves at least [minPaneWidth] for the ops pane when space allows;
/// when the window is too narrow for both floors, room pane shrinks first so
/// ops keeps a readable share (avoids CustomScrollView layout crashes at
/// ~100px cross-axis extents).
double beaconViewRoomSplitPaneWidth(
  TenturaTokens tt, {
  double? availableWidth,
  double minPaneWidth = 360.0,
  double? preferredWidth,
}) {
  final minChat = minPaneWidth;
  final minOps = minPaneWidth;
  if (availableWidth == null || !availableWidth.isFinite) {
    final ideal = preferredWidth ?? tt.chatColumnMaxWidth;
    return ideal.clamp(minChat, math.max(minChat, tt.chatColumnMaxWidth));
  }

  final maxForChat = math.max(0.0, availableWidth - minOps);
  final defaultWidth = math.min(tt.chatColumnMaxWidth, availableWidth * 0.42);
  final ideal = preferredWidth ?? defaultWidth;
  // When both floors cannot fit, lower == maxForChat and ops keeps minOps.
  final lower = math.min(minChat, maxForChat);
  return ideal.clamp(lower, maxForChat);
}

/// Restores Home's persistent side navigation while a root browse-detail
/// route covers the Home page on a non-compact window.
class _BeaconViewHomeRail extends StatelessWidget {
  const _BeaconViewHomeRail({
    required this.selectedIndex,
    required this.child,
  });

  final int selectedIndex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (context.windowClass == WindowClass.compact) return child;

    final l10n = L10n.of(context)!;
    final extended = context.windowClass == WindowClass.expanded;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NavigationRail(
          extended: extended,
          selectedIndex: selectedIndex,
          onDestinationSelected: (index) {
            final spec = HomeTabSpec.fromIndex(index);
            if (spec == null) return;
            final root = context.router.root;
            root
                .innerRouterOf<TabsRouter>(HomeRoute.name)
                ?.setActiveIndex(index);
            unawaited(root.replacePath(spec.path));
          },
          labelType: extended
              ? NavigationRailLabelType.none
              : NavigationRailLabelType.all,
          destinations: [
            NavigationRailDestination(
              icon: const Icon(Icons.work_outline),
              selectedIcon: const Icon(Icons.work),
              label: Text(l10n.myWork),
            ),
            NavigationRailDestination(
              icon: const Icon(Icons.inbox_outlined),
              selectedIcon: const Icon(Icons.inbox),
              label: Text(l10n.inbox),
            ),
            NavigationRailDestination(
              icon: const Icon(TenturaIcons.graph),
              selectedIcon: const Icon(TenturaIcons.graph),
              label: Text(l10n.constellationNavLabel),
            ),
            NavigationRailDestination(
              icon: const Icon(Icons.people_outline),
              selectedIcon: const Icon(Icons.people),
              label: Text(l10n.network),
            ),
            NavigationRailDestination(
              icon: const Icon(Icons.person_outline),
              selectedIcon: const Icon(Icons.person),
              label: Text(l10n.profile),
            ),
          ],
        ),
        const TenturaVerticalHairline(),
        Expanded(child: child),
      ],
    );
  }
}

class BeaconViewScreen extends StatefulWidget {
  const BeaconViewScreen({
    this.id = '',
    this.isDeepLink,
    this.viewTab,
    this.peopleTabAttention,
    this.entry,
    this.threadId,
    this.messageId,
    super.key,
  });

  final String id;

  final String? isDeepLink;

  /// `now` | `threads` | `people` | `log`.
  final String? viewTab;

  /// With [viewTab]=`people`, truthy values pulse/highlight the People tab until interaction.
  final String? peopleTabAttention;

  /// Entry provenance ([kQueryBeaconEntry]).
  final String? entry;

  /// Expanded split / deep-link thread selection (`general` or item id).
  final String? threadId;

  /// Exact Chat message target from an Updates receipt.
  final String? messageId;

  @override
  State<BeaconViewScreen> createState() => _BeaconViewScreenState();
}

class _BeaconViewScreenState extends State<BeaconViewScreen> {
  late BeaconSurface _selectedSurface;
  late bool _peopleTabAttentionActive;

  /// Thread row to scroll-to + flash after a Log row tap.
  String? _focusThreadId;
  String? _focusUserId;

  /// Remount People accordion folds on same-tab reselect.
  int _peopleFoldEpoch = 0;

  /// Remount Threads accordion folds on same-tab reselect.
  int _threadsFoldEpoch = 0;

  bool _didApplyThreadsResolution = false;
  String? _bannerMessage;

  /// User drag override for the room pane width; null = token default.
  double? _roomPaneWidthOverride;

  /// Latched on first successful non-empty [ThreadsState]; reset on beacon id change.
  bool _hadThreadRowsAtLeastOnce = false;

  /// Tracks the previous split state for surface reselection on resize edges.
  bool? _lastIsSplit;

  BeaconRoomLease? _roomLease;

  /// One-shot scroll targets when opening Chat from coordination / log focus.
  String? _roomScrollMessageId;
  String? _roomScrollCoordinationItemId;

  /// Guards legacy `?tab=log` from opening the Activity sheet twice.
  bool _didOpenActivitySheetForLogTab = false;

  void _leaveBeaconView(BuildContext context) {
    final router = context.router;

    if (router.canPop()) {
      unawaited(router.maybePop());
      return;
    }

    final parent = router.parent<StackRouter>();
    if (parent != null && parent.canPop()) {
      unawaited(parent.maybePop());
      return;
    }

    // In deep-linked direct detail views we still want the back button to go back.
    // However, if we pop, we would pop out of the app.
    // Since we are inside Inbox, let's navigate to Inbox Route instead.
    final rootRouter = context.router.root;
    final tab = rootRouter
        .innerRouterOf<TabsRouter>(HomeRoute.name)
        ?.activeIndex;

    // Only route to inbox if we are actually mounted inside the inbox tab.
    // In deep link operations we could be in 'My Work' tab.
    final isInboxTab =
        tab != null && tab == HomeTabSpec.forTab(HomeTab.inbox).index;

    // Similarly, we can navigate to other tabs by looking up the tab index.
    final isUpdatesTab =
        tab != null && tab == HomeTabSpec.forTab(HomeTab.updates).index;
    final isNetworkTab =
        tab != null && tab == HomeTabSpec.forTab(HomeTab.network).index;

    final path = isInboxTab
        ? kPathInbox
        : isUpdatesTab
        ? kPathUpdates
        : isNetworkTab
        ? kPathNetwork
        : kPathMyWork;

    unawaited(router.root.replacePath(path));
  }

  Widget _beaconViewErrorBody({
    required ThemeData theme,
    required ColorScheme scheme,
    required TenturaTokens tt,
    required String title,
    required String body,
    required VoidCallback onRetry,
    required VoidCallback onGoBack,
    required String retryLabel,
    required String goBackLabel,
  }) {
    return Center(
      child: Padding(
        padding: EdgeInsets.all(tt.screenHPadding),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.error_outline,
              size: tt.iconSize * 2,
              color: scheme.error,
            ),
            SizedBox(height: tt.sectionGap),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: tt.rowGap),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            SizedBox(height: tt.sectionGap),
            FilledButton(
              onPressed: onRetry,
              child: Text(retryLabel),
            ),
            TextButton(
              onPressed: onGoBack,
              child: Text(goBackLabel),
            ),
          ],
        ),
      ),
    );
  }

  String _beaconViewPath({
    String? viewTab,
    String? threadId,
  }) {
    final q = <String, String>{};
    if (viewTab != null && viewTab.isNotEmpty) {
      q[kQueryBeaconViewTab] = viewTab;
    }
    if (threadId != null && threadId.isNotEmpty) {
      q[kQueryThreadId] = threadId;
    }
    final entry = widget.entry?.trim();
    if (entry != null && entry.isNotEmpty) {
      q[kQueryBeaconEntry] = entry;
    }
    final base = '$kPathBeaconView/${widget.id}';
    if (q.isEmpty) return base;
    return '$base?${Uri(queryParameters: q).query}';
  }

  Future<void> _syncSurfaceQuery(
    BeaconSurface surface, {
    String? threadId,
  }) {
    return context.router.replacePath(
      _beaconViewPath(
        viewTab: _beaconSurfaceViewTab(surface),
        threadId: threadId,
      ),
    );
  }

  Future<void> _syncExpandedThreadQuery(String? threadId) {
    // BeaconViewRoute is a root browse-detail route. Replacing it through the
    // tab branch turns `beacon/view/:id` into an unmatched relative path, so
    // AutoRoute falls back to My Work while retaining the query parameters.
    return _syncSurfaceQuery(BeaconSurface.room, threadId: threadId);
  }

  BeaconRoomLease _ensureRoomLease() =>
      _roomLease ??= BeaconRoomLease(host: context.read<ThreadHostCubit>());

  bool _computeIsSplit({
    required double availableWidth,
    required bool showBeaconContent,
  }) {
    const minPaneWidth = 360.0;
    const splitHandleWidth = TenturaSpacing.row;
    return availableWidth >= minPaneWidth * 2 + splitHandleWidth &&
        beaconViewUsesExpandedThreadSplit(
          windowClass: context.windowClass,
          showBeaconContent: showBeaconContent,
          hasThreadRows: _hadThreadRowsAtLeastOnce,
        );
  }

  RequestThread? _generalThread(ThreadsState state) => state.general;

  bool _isLegacyThreadId(String? threadId) {
    final id = threadId?.trim();
    if (id == null || id.isEmpty) return false;
    return id != RequestThread.generalId;
  }

  Future<void> _applyThreadsResolution({
    required ThreadsState threadsState,
    required bool isSplit,
  }) async {
    if (!threadsState.isSuccess || _didApplyThreadsResolution) return;
    if (!isSplit) return;
    _didApplyThreadsResolution = true;

    if (_isLegacyThreadId(widget.threadId)) return;

    final host = context.read<ThreadHostCubit>();
    if (host.state.openThreadId != null) return;

    final row = _generalThread(threadsState);
    if (row == null) return;

    // Split-pane [BeaconRoomSurface] owns the lease acquire; scroll once ready.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final host = context.read<ThreadHostCubit>();
      final messageId = widget.messageId?.trim();
      if (_ensureRoomLease().isReady &&
          messageId != null &&
          messageId.isNotEmpty) {
        host.roomCubit?.prepareThreadScroll(messageId: messageId);
      }
    });
    unawaited(_syncExpandedThreadQuery(RequestThread.generalId));
  }

  Future<void> _openGeneralDiscussion({
    required bool isSplit,
    String? messageId,
    String? coordinationItemId,
  }) async {
    final threadsState = context.read<ThreadsCubit>().state;
    final row = _generalThread(threadsState);
    if (row == null) return;

    if (!isSplit) {
      setState(() {
        _selectedSurface = BeaconSurface.room;
        _roomScrollMessageId = messageId;
        _roomScrollCoordinationItemId = coordinationItemId;
        _bannerMessage = null;
        _peopleTabAttentionActive = false;
        _focusThreadId = null;
        _focusUserId = null;
      });
      unawaited(_syncSurfaceQuery(BeaconSurface.room));
      return;
    }

    final scrollMessageId = messageId?.trim();
    final itemId = coordinationItemId?.trim();
    if ((scrollMessageId != null && scrollMessageId.isNotEmpty) ||
        (itemId != null && itemId.isNotEmpty)) {
      context.read<ThreadHostCubit>().roomCubit?.prepareThreadScroll(
        messageId: scrollMessageId,
        coordinationItemId: itemId,
      );
    }
    unawaited(_syncExpandedThreadQuery(RequestThread.generalId));
  }

  Future<void> _openGeneralThread({
    String? messageId,
    String? coordinationItemId,
  }) async {
    final showBeaconContent =
        context.read<BeaconViewCubit>().state.beaconContentLoaded &&
        !context.read<BeaconViewCubit>().state.beaconUnavailable;
    final isSplit = _computeIsSplit(
      availableWidth: MediaQuery.sizeOf(context).width,
      showBeaconContent: showBeaconContent,
    );

    await _openGeneralDiscussion(
      isSplit: isSplit,
      messageId: messageId,
      coordinationItemId: coordinationItemId,
    );
  }

  void _onOpenCoordinationItemFromThread(CoordinationItem item) {
    if (planItemSuppressesItemDiscussion(item)) {
      context.read<ThreadHostCubit>().roomCubit?.prepareThreadScroll(
        messageId: item.threadAnchorMessageId,
        coordinationItemId: item.id,
      );
      return;
    }
    unawaited(
      _openGeneralThread(
        messageId: item.threadAnchorMessageId,
        coordinationItemId: item.id,
      ),
    );
  }

  void _refreshThreadsTab() {
    unawaited(context.read<ThreadsCubit>().fetch());
  }

  void _maybeOpenActivitySheetForLogTab() {
    if (widget.viewTab != 'log' || _didOpenActivitySheetForLogTab) return;
    _didOpenActivitySheetForLogTab = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openActivitySheet());
    });
  }

  Future<void> _openActivitySheet() async {
    if (!mounted) return;
    final cubit = context.read<BeaconViewCubit>();
    await showBeaconActivitySheet(
      context,
      cubit: cubit,
      onTapCoordinationEvent: _onTapCoordinationLogEvent,
    );
  }

  void _scheduleSplitEdgeHandling({required bool isSplit}) {
    final previous = _lastIsSplit;
    _lastIsSplit = isSplit;

    void applyEdge() {
      if (!mounted) return;
      if (previous == null) {
        if (isSplit && _selectedSurface == BeaconSurface.room) {
          _switchToSurface(BeaconSurface.now, syncQuery: false);
        }
        return;
      }
      if (previous == isSplit) return;

      if (isSplit && _selectedSurface == BeaconSurface.room) {
        _switchToSurface(BeaconSurface.now, syncQuery: true);
      } else if (!isSplit && previous) {
        _switchToSurface(BeaconSurface.room, syncQuery: true);
      }
    }

    if (previous == null &&
        !(isSplit && _selectedSurface == BeaconSurface.room)) {
      return;
    }
    if (previous != null && previous == isSplit) return;

    WidgetsBinding.instance.addPostFrameCallback((_) => applyEdge());
  }

  @override
  void initState() {
    super.initState();
    _selectedSurface = _beaconViewSurface(widget.viewTab);
    _peopleTabAttentionActive =
        _beaconPeopleTabAttentionQueryTruthy(widget.peopleTabAttention) &&
        _selectedSurface == BeaconSurface.people;
    if (widget.viewTab == 'log') {
      _maybeOpenActivitySheetForLogTab();
    }
  }

  @override
  void dispose() {
    _roomLease?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(BeaconViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _didApplyThreadsResolution = false;
      _focusThreadId = null;
      _focusUserId = null;
      _roomPaneWidthOverride = null;
      _hadThreadRowsAtLeastOnce = false;
      _lastIsSplit = null;
      _didOpenActivitySheetForLogTab = false;
    }
    if (oldWidget.viewTab != widget.viewTab) {
      _selectedSurface = _beaconViewSurface(widget.viewTab);
      if (widget.viewTab == 'log') {
        _maybeOpenActivitySheetForLogTab();
      }
    }
  }

  void _switchToSurface(BeaconSurface surface, {bool syncQuery = true}) {
    if (_selectedSurface == surface) {
      if (syncQuery) unawaited(_syncSurfaceQuery(surface));
      return;
    }
    setState(() {
      if (_selectedSurface == BeaconSurface.people &&
          surface != BeaconSurface.people) {
        _peopleTabAttentionActive = false;
      }
      _selectedSurface = surface;
      _bannerMessage = null;
      _focusThreadId = null;
      _focusUserId = null;
    });
    if (syncQuery) {
      unawaited(_syncSurfaceQuery(surface));
    }
  }

  void _activatePeopleTabAttention() {
    setState(() {
      _selectedSurface = BeaconSurface.people;
      _peopleTabAttentionActive = true;
      _bannerMessage = null;
      _focusThreadId = null;
      _focusUserId = null;
    });
    unawaited(_syncSurfaceQuery(BeaconSurface.people));
  }

  void _focusDiscussionGeneral() {
    setState(() {
      _selectedSurface = BeaconSurface.room;
      _focusThreadId = RequestThread.generalId;
      _focusUserId = null;
      _bannerMessage = null;
      _peopleTabAttentionActive = false;
    });
    unawaited(_syncSurfaceQuery(BeaconSurface.room));
  }

  void _onTapCoordinationLogEvent(BeaconActivityEvent e) {
    final kind = e.coordinationKind;
    final itemId = e.coordinationItemId?.trim();

    if (kind == CoordinationItemKind.ask ||
        kind == CoordinationItemKind.promise ||
        kind == CoordinationItemKind.blocker) {
      _focusDiscussionGeneral();
      return;
    }

    if (kind == CoordinationItemKind.plan) {
      setState(() {
        _selectedSurface = BeaconSurface.room;
        _focusThreadId = null;
        _focusUserId = null;
        _bannerMessage = null;
        _peopleTabAttentionActive = false;
      });
      final messageId = e.sourceMessageId?.trim();
      unawaited(
        _openGeneralThread(
          messageId: messageId,
          coordinationItemId: itemId,
        ),
      );
      return;
    }

    final userId = (e.targetUserId ?? e.actorId)?.trim();
    if (userId != null && userId.isNotEmpty) {
      setState(() {
        _selectedSurface = BeaconSurface.people;
        _focusUserId = userId;
        _focusThreadId = null;
        _bannerMessage = null;
        _peopleTabAttentionActive = false;
      });
      unawaited(_syncSurfaceQuery(BeaconSurface.people));
    }
  }

  void _clearOperationalFocus() {
    if (_focusThreadId == null && _focusUserId == null) return;
    setState(() {
      _focusThreadId = null;
      _focusUserId = null;
    });
  }

  void _onSurfaceReselected(BeaconSurface surface) {
    if (surface == BeaconSurface.people || surface == BeaconSurface.room) {
      _clearOperationalFocus();
    }
    setState(() {
      if (surface == BeaconSurface.people) {
        _peopleFoldEpoch++;
      } else if (surface == BeaconSurface.room) {
        _threadsFoldEpoch++;
        _refreshThreadsTab();
      }
    });
  }

  Widget _buildTabRow({
    required bool isSplit,
    required TenturaTokens tt,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: tt.borderSubtle)),
      ),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: tt.screenHPadding),
        child: BeaconSurfaceTabs(
          isSplit: isSplit,
          selectedSurface: _selectedSurface,
          onSurfaceSelected: _switchToSurface,
          onSurfaceReselected: _onSurfaceReselected,
          peopleTabAttentionActive: _peopleTabAttentionActive,
        ),
      ),
    );
  }

  Widget _buildSelectedSurface({
    required BeaconViewCubit beaconViewCubit,
    required ScreenCubit screenCubit,
    required BeaconViewState beaconState,
    required bool isSplit,
    required BeaconRoomLease roomLease,
  }) {
    final surface = isSplit && _selectedSurface == BeaconSurface.room
        ? BeaconSurface.now
        : _selectedSurface;

    switch (surface) {
      case BeaconSurface.now:
        return BeaconNowSurface(
          beaconViewCubit: beaconViewCubit,
          screenCubit: screenCubit,
          beaconState: beaconState,
          onSurfaceSelected: _switchToSurface,
          onActivatePeopleTabAttention: _activatePeopleTabAttention,
          onFocusCoordinationItem: (_) => _focusDiscussionGeneral(),
          onOpenGeneralThread: () => unawaited(_openGeneralThread()),
        );
      case BeaconSurface.room:
        return BeaconRoomSurface(
          key: ValueKey('room-$_threadsFoldEpoch'),
          beaconViewCubit: beaconViewCubit,
          roomLease: roomLease,
          legacyThreadId: widget.threadId,
          messageId: _roomScrollMessageId ?? widget.messageId,
          coordinationItemId: _roomScrollCoordinationItemId,
          onCoordinationSaved: _refreshThreadsTab,
          onOpenCoordinationItem: _onOpenCoordinationItemFromThread,
        );
      case BeaconSurface.people:
        return BeaconPeopleSurface(
          beaconViewCubit: beaconViewCubit,
          beaconState: beaconState,
          focusUserId: _focusUserId,
          peopleTabAttentionActive: _peopleTabAttentionActive,
          peopleFoldEpoch: _peopleFoldEpoch,
        );
    }
  }

  Widget _buildTabbedContent({
    required BeaconViewCubit beaconViewCubit,
    required ScreenCubit screenCubit,
    required BeaconViewState beaconState,
    required bool isSplit,
    required BeaconRoomLease roomLease,
  }) {
    return TenturaContentColumn(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabRow(isSplit: isSplit, tt: context.tt),
          Expanded(
            child: _buildSelectedSurface(
              beaconViewCubit: beaconViewCubit,
              screenCubit: screenCubit,
              beaconState: beaconState,
              isSplit: isSplit,
              roomLease: roomLease,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedSplitBody({
    required BeaconViewState beaconState,
    required BeaconViewCubit beaconViewCubit,
    required ScreenCubit screenCubit,
    required ThreadsState threadsState,
    required ThreadHostState hostState,
    required TenturaTokens tt,
    required BeaconRoomLease roomLease,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const handleWidth = TenturaSpacing.row;
        const minPane = 360.0;
        final threadPaneWidth = beaconViewRoomSplitPaneWidth(
          tt,
          availableWidth: constraints.maxWidth - handleWidth,
          minPaneWidth: minPane,
          preferredWidth: _roomPaneWidthOverride,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildTabbedContent(
                beaconViewCubit: beaconViewCubit,
                screenCubit: screenCubit,
                beaconState: beaconState,
                isSplit: true,
                roomLease: roomLease,
              ),
            ),
            TenturaVerticalResizeHandle(
              onDragDelta: (dx) {
                // Room pane is on the right: drag left (negative dx) widens it.
                setState(() {
                  _roomPaneWidthOverride = beaconViewRoomSplitPaneWidth(
                    tt,
                    availableWidth: constraints.maxWidth - handleWidth,
                    minPaneWidth: minPane,
                    preferredWidth: threadPaneWidth - dx,
                  );
                });
              },
            ),
            SizedBox(
              width: threadPaneWidth,
              child: BeaconRoomSurface(
                beaconViewCubit: beaconViewCubit,
                roomLease: roomLease,
                legacyThreadId: widget.threadId,
                messageId: widget.messageId,
                onCoordinationSaved: _refreshThreadsTab,
                onOpenCoordinationItem: _onOpenCoordinationItemFromThread,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _splitThreadPaneAppBar({
    required ThreadsState threadsState,
    required ThreadHostState hostState,
    required BeaconViewState beaconState,
    required L10n l10n,
    required Widget overflow,
  }) {
    final thread = _generalThread(threadsState);
    if (thread == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: overflow,
      );
    }

    final title = ThreadDetailGeneralTitle(
      title: threadGeneralAppBarTitle(l10n, beaconState.beacon),
      beacon: beaconState.beacon,
      involvedProfiles: beaconState.activeHelpOfferUsers,
      currentUserId: beaconState.myProfile.id,
    );

    return Row(
      children: [
        Expanded(child: title),
        overflow,
      ],
    );
  }

  Widget _buildAppBarTitle({
    required bool isSplit,
    required BeaconViewState state,
    required bool showBeaconContent,
    required L10n l10n,
  }) {
    if (isSplit) return const SizedBox.shrink();

    if (_selectedSurface == BeaconSurface.room && showBeaconContent) {
      return ThreadDetailGeneralTitle(
        title: threadGeneralAppBarTitle(l10n, state.beacon),
        beacon: state.beacon,
        involvedProfiles: state.activeHelpOfferUsers,
        currentUserId: state.myProfile.id,
        onFacePileTap: () => _switchToSurface(BeaconSurface.people),
      );
    }

    return BeaconViewAppBarTitle(
      beacon: state.beacon,
      showBeaconContent: showBeaconContent,
      phaseStatus: beaconViewStatusSlots(l10n, state).presentation,
      l10n: l10n,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final beaconViewCubit = context.read<BeaconViewCubit>();
    final l10n = L10n.of(context)!;
    final roomLease = _ensureRoomLease();

    return MultiBlocListener(
      listeners: [
        BlocListener<ThreadsCubit, ThreadsState>(
          listenWhen: (p, c) =>
              c.isSuccess && c.threads.isNotEmpty && !_hadThreadRowsAtLeastOnce,
          listener: (context, threadsState) {
            setState(() => _hadThreadRowsAtLeastOnce = true);
          },
        ),
        BlocListener<ThreadsCubit, ThreadsState>(
          listenWhen: (p, c) => !p.isSuccess && c.isSuccess,
          listener: (context, threadsState) {
            final beaconState = beaconViewCubit.state;
            final showBeaconContent =
                beaconState.beaconContentLoaded &&
                !beaconState.beaconUnavailable;
            final isSplit = _computeIsSplit(
              availableWidth: MediaQuery.sizeOf(context).width,
              showBeaconContent: showBeaconContent,
            );
            unawaited(
              _applyThreadsResolution(
                threadsState: threadsState,
                isSplit: isSplit,
              ),
            );
          },
        ),
      ],
      child: BlocBuilder<BeaconViewCubit, BeaconViewState>(
        bloc: beaconViewCubit,
        buildWhen: (p, c) =>
            c.isSuccess ||
            c.isLoading ||
            c.hasError ||
            p.beaconContentLoaded != c.beaconContentLoaded ||
            p.beaconContextLoaded != c.beaconContextLoaded ||
            p.beaconUnavailable != c.beaconUnavailable ||
            p.beacon != c.beacon ||
            p.helpOffers != c.helpOffers ||
            p.isRoomAdmissionBlocked != c.isRoomAdmissionBlocked ||
            p.coordinationDeniesRoomAdmission !=
                c.coordinationDeniesRoomAdmission,
        builder: (context, state) {
          return BlocBuilder<ThreadsCubit, ThreadsState>(
            buildWhen: (p, c) => p.status != c.status || p.threads != c.threads,
            builder: (context, threadsState) {
              return BlocBuilder<ThreadHostCubit, ThreadHostState>(
                buildWhen: (p, c) =>
                    p.openThreadId != c.openThreadId ||
                    p.switching != c.switching,
                builder: (context, hostState) {
                  final theme = Theme.of(context);
                  final scheme = theme.colorScheme;
                  final tt = context.tt;
                  final showInitialLoading =
                      state.isLoading &&
                      !state.beaconContentLoaded &&
                      state.timeline.isEmpty &&
                      state.helpOffers.isEmpty;
                  final showInitialUnavailable = state.beaconUnavailable;
                  final showInitialError =
                      state.hasError &&
                      !showInitialUnavailable &&
                      state.timeline.isEmpty &&
                      state.helpOffers.isEmpty;
                  final showBeaconContent =
                      state.beaconContentLoaded && !state.beaconUnavailable;

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      const minPaneWidth = 360.0;
                      const splitHandleWidth = TenturaSpacing.row;
                      final isSplit =
                          constraints.maxWidth >=
                              minPaneWidth * 2 + splitHandleWidth &&
                          _computeIsSplit(
                            availableWidth: constraints.maxWidth,
                            showBeaconContent: showBeaconContent,
                          );

                      _scheduleSplitEdgeHandling(isSplit: isSplit);

                      if (threadsState.isSuccess && isSplit) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (!mounted) return;
                          unawaited(
                            _applyThreadsResolution(
                              threadsState: threadsState,
                              isSplit: true,
                            ),
                          );
                        });
                      }

                      final statusSlots = beaconViewStatusSlots(l10n, state);
                      final appBarPhaseStatus = statusSlots.presentation;

                      Widget body;
                      if (showInitialLoading) {
                        body = const Center(
                          child: CircularProgressIndicator.adaptive(),
                        );
                      } else if (showInitialUnavailable) {
                        body = _beaconViewErrorBody(
                          theme: theme,
                          scheme: scheme,
                          tt: tt,
                          title: l10n.beaconHudBeaconUnavailable,
                          body: l10n.beaconViewUnavailableBody,
                          retryLabel: l10n.myWorkRetry,
                          goBackLabel: l10n.beaconViewErrorGoBack,
                          onRetry: () =>
                              unawaited(beaconViewCubit.retryInitialLoad()),
                          onGoBack: () => _leaveBeaconView(context),
                        );
                      } else if (showInitialError) {
                        body = _beaconViewErrorBody(
                          theme: theme,
                          scheme: scheme,
                          tt: tt,
                          title: l10n.beaconHudBeaconUnavailable,
                          body: l10n.beaconViewLoadErrorBody,
                          retryLabel: l10n.myWorkRetry,
                          goBackLabel: l10n.beaconViewErrorGoBack,
                          onRetry: () =>
                              unawaited(beaconViewCubit.retryInitialLoad()),
                          onGoBack: () => _leaveBeaconView(context),
                        );
                      } else if (isSplit) {
                        body = _buildExpandedSplitBody(
                          beaconState: state,
                          beaconViewCubit: beaconViewCubit,
                          screenCubit: screenCubit,
                          threadsState: threadsState,
                          hostState: hostState,
                          tt: tt,
                          roomLease: roomLease,
                        );
                      } else {
                        body = _buildTabbedContent(
                          beaconViewCubit: beaconViewCubit,
                          screenCubit: screenCubit,
                          beaconState: state,
                          isSplit: false,
                          roomLease: roomLease,
                        );
                      }

                      final contentColumn = Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (_bannerMessage != null)
                            MaterialBanner(
                              content: Text(_bannerMessage!),
                              actions: [
                                TextButton(
                                  onPressed: () =>
                                      setState(() => _bannerMessage = null),
                                  child: Text(l10n.beaconViewBannerDismiss),
                                ),
                              ],
                            ),
                          Expanded(child: body),
                        ],
                      );

                      // Keep canPop true on NOW so the plain "leave the request"
                      // path never goes through a blocking PopScope (Flutter Web
                      // history sentinel on canPop:false made AppBar back a no-op
                      // when a ThreadDetail child was open — that child route goes
                      // away in U10, but the leave path must stay unblocked).
                      return BeaconRoomNavigationScope(
                        isRoomPresented: isBeaconRoomPresented(
                          isSplit: isSplit,
                          selectedSurface: _selectedSurface,
                        ),
                        roomLease: roomLease,
                        openGeneralAnchor: ({messageId, coordinationItemId}) =>
                            _openGeneralThread(
                              messageId: messageId,
                              coordinationItemId: coordinationItemId,
                            ),
                        child: PopScope(
                        canPop: _selectedSurface == BeaconSurface.now,
                        onPopInvokedWithResult: (didPop, result) {
                          if (didPop) return;
                          if (_selectedSurface == BeaconSurface.room ||
                              _selectedSurface == BeaconSurface.people) {
                            _switchToSurface(BeaconSurface.now);
                          }
                        },
                        child: Scaffold(
                          appBar: TenturaTopBar.of(
                            context,
                            alignment: isSplit
                                ? TenturaTopBarAlignment.fullWidth
                                : TenturaTopBarAlignment.content,
                            leading: isSplit
                                ? null
                                : AutoLeadingWithFallback(
                                    fallbackPath: kPathMyWork,
                                    onFallback: () => _leaveBeaconView(context),
                                  ),
                            title: _buildAppBarTitle(
                              isSplit: isSplit,
                              state: state,
                              showBeaconContent: showBeaconContent,
                              l10n: l10n,
                            ),
                            actions: isSplit
                                ? null
                                : [
                                    if (showBeaconContent)
                                      beaconViewAppBarOverflow(
                                        context: context,
                                        state: state,
                                        cubit: beaconViewCubit,
                                        screenCubit: screenCubit,
                                        l10n: l10n,
                                        inRoomSurface:
                                            _selectedSurface ==
                                            BeaconSurface.room,
                                        roomCubit: context
                                            .read<ThreadHostCubit>()
                                            .roomCubit,
                                        onItemsTabRefresh: _refreshThreadsTab,
                                        onActivityLog: () =>
                                            unawaited(_openActivitySheet()),
                                        onAuthorManageStatus: () async {
                                          await beaconViewCubit
                                              .refreshReviewWindowInfo();
                                          if (!context.mounted) return;
                                          await showBeaconViewUpdateStatusSheet(
                                            context,
                                            beaconViewCubit.state,
                                            beaconViewCubit,
                                            onOpenPeopleTab: () =>
                                                _switchToSurface(
                                                  BeaconSurface.people,
                                                ),
                                            onOpenGeneralThread: () =>
                                                unawaited(_openGeneralThread()),
                                          );
                                        },
                                      ),
                                  ],
                            row: isSplit
                                ? LayoutBuilder(
                                    builder: (context, constraints) {
                                      const handleWidth = TenturaSpacing.row;
                                      final threadPaneWidth =
                                          beaconViewRoomSplitPaneWidth(
                                            tt,
                                            availableWidth:
                                                constraints.maxWidth -
                                                handleWidth,
                                            preferredWidth:
                                                _roomPaneWidthOverride,
                                          );
                                      final managementOverflow =
                                          showBeaconContent
                                          ? beaconViewAppBarOverflow(
                                              context: context,
                                              state: state,
                                              cubit: beaconViewCubit,
                                              screenCubit: screenCubit,
                                              l10n: l10n,
                                              inRoomSurface: false,
                                              roomCubit: context
                                                  .read<ThreadHostCubit>()
                                                  .roomCubit,
                                              onItemsTabRefresh:
                                                  _refreshThreadsTab,
                                              onActivityLog: () => unawaited(
                                                _openActivitySheet(),
                                              ),
                                              onAuthorManageStatus: () async {
                                                await beaconViewCubit
                                                    .refreshReviewWindowInfo();
                                                if (!context.mounted) return;
                                                await showBeaconViewUpdateStatusSheet(
                                                  context,
                                                  beaconViewCubit.state,
                                                  beaconViewCubit,
                                                  onOpenPeopleTab: () =>
                                                      _switchToSurface(
                                                        BeaconSurface.people,
                                                      ),
                                                  onOpenGeneralThread: () =>
                                                      unawaited(
                                                        _openGeneralThread(),
                                                      ),
                                                );
                                              },
                                            )
                                          : const SizedBox.shrink();
                                      final roomOverflow = showBeaconContent
                                          ? beaconViewAppBarOverflow(
                                              context: context,
                                              state: state,
                                              cubit: beaconViewCubit,
                                              screenCubit: screenCubit,
                                              l10n: l10n,
                                              inRoomSurface: true,
                                              roomCubit: context
                                                  .read<ThreadHostCubit>()
                                                  .roomCubit,
                                              onItemsTabRefresh:
                                                  _refreshThreadsTab,
                                              onActivityLog: () => unawaited(
                                                _openActivitySheet(),
                                              ),
                                              onAuthorManageStatus: () async {
                                                await beaconViewCubit
                                                    .refreshReviewWindowInfo();
                                                if (!context.mounted) return;
                                                await showBeaconViewUpdateStatusSheet(
                                                  context,
                                                  beaconViewCubit.state,
                                                  beaconViewCubit,
                                                  onOpenPeopleTab: () =>
                                                      _switchToSurface(
                                                        BeaconSurface.people,
                                                      ),
                                                  onOpenGeneralThread: () =>
                                                      unawaited(
                                                        _openGeneralThread(),
                                                      ),
                                                );
                                              },
                                            )
                                          : const SizedBox.shrink();
                                      return Row(
                                        children: [
                                          Expanded(
                                            child: TenturaContentColumn(
                                              child: Row(
                                                children: [
                                                  AutoLeadingWithFallback(
                                                    fallbackPath: kPathMyWork,
                                                    onFallback: () =>
                                                        _leaveBeaconView(
                                                          context,
                                                        ),
                                                  ),
                                                  Expanded(
                                                    child: BeaconViewAppBarTitle(
                                                      beacon: state.beacon,
                                                      showBeaconContent:
                                                          showBeaconContent,
                                                      phaseStatus:
                                                          appBarPhaseStatus,
                                                      l10n: l10n,
                                                    ),
                                                  ),
                                                  managementOverflow,
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: handleWidth),
                                          SizedBox(
                                            width: threadPaneWidth,
                                            child: _splitThreadPaneAppBar(
                                              threadsState: threadsState,
                                              hostState: hostState,
                                              beaconState: state,
                                              l10n: l10n,
                                              overflow: roomOverflow,
                                            ),
                                          ),
                                        ],
                                      );
                                    },
                                  )
                                : null,
                            progress: TenturaTopBar.loadingBar(
                              context,
                              state.isLoading,
                            ),
                          ),
                          body: _BeaconViewHomeRail(
                            selectedIndex: switch (widget.entry) {
                              kBeaconEntryInbox => HomeTabSpec.forTab(
                                HomeTab.inbox,
                              ).index,
                              kBeaconEntryRoomNotification =>
                                HomeTabSpec.forTab(HomeTab.updates).index,
                              _ => HomeTabSpec.forTab(HomeTab.work).index,
                            },
                            child: SafeArea(child: contentColumn),
                          ),
                        ),
                      ),
                    );
                    },
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
