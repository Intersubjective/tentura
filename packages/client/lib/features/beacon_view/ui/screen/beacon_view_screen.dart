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
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../widget/beacon_anchor_status.dart';
import '../widget/beacon_operational_scroll_view.dart';
import '../widget/beacon_view_app_bar_overflow.dart';
import '../widget/beacon_view_app_bar_title.dart';
import '../widget/beacon_view_status_bottom_sheet.dart';
import '../widget/beacon_view_constants.dart';

bool _beaconPeopleTabAttentionQueryTruthy(String? v) {
  if (v == null || v.isEmpty) return false;
  final s = v.toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

/// Query [kQueryBeaconViewTab]: `threads` | `people` | `log`.
int _beaconViewTabIndex(String? viewTab) {
  switch (viewTab) {
    case 'people':
      return kBeaconTabPeople;
    case 'log':
      return kBeaconTabLog;
    case 'threads':
    default:
      return kBeaconTabThreads;
  }
}

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
              icon: const Icon(Icons.notifications_none),
              selectedIcon: const Icon(Icons.notifications),
              label: Text(l10n.updatesTitle),
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

  /// `threads` | `people` | `log`.
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
  late int _tabIndex;
  late bool _peopleTabAttentionActive;

  /// Thread row to scroll-to + flash after a Log row tap.
  String? _focusThreadId;
  String? _focusUserId;

  bool _didApplyThreadsResolution = false;
  String? _bannerMessage;
  WindowClass? _lastWindowClass;

  /// User drag override for the room pane width; null = token default.
  double? _roomPaneWidthOverride;

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

  Future<void> _syncExpandedThreadQuery(String? threadId) {
    // BeaconViewRoute is a root browse-detail route. Replacing it through the
    // tab branch turns `beacon/view/:id` into an unmatched relative path, so
    // AutoRoute falls back to My Work while retaining the query parameters.
    return context.router.replacePath(
      _beaconViewPath(
        viewTab: kBeaconViewTabThreads,
        threadId: threadId,
      ),
    );
  }

  bool _usesExpandedThreadSplit({
    required bool showBeaconContent,
    required ThreadsState threadsState,
  }) {
    final hasThreadRows =
        threadsState.isSuccess && threadsState.threads.isNotEmpty;
    if (!showBeaconContent || !hasThreadRows) return false;
    return beaconViewUsesExpandedThreadSplit(
      windowClass: context.windowClass,
      showBeaconContent: showBeaconContent,
      hasThreadRows: hasThreadRows,
    );
  }

  RequestThread? _resolveThreadRow(ThreadsState state, String threadId) {
    for (final thread in state.threads) {
      if (thread.threadId == threadId) {
        return thread;
      }
    }
    return null;
  }

  RequestThread? _resolveAccessibleRow(ThreadsState state, String? threadId) {
    final explicit = threadId?.trim();
    if (explicit != null && explicit.isNotEmpty) {
      final row = _resolveThreadRow(state, explicit);
      if (row != null) return row;
    }
    return state.firstAccessible;
  }

  RequestThread? _selectedThread(
    ThreadsState threadsState,
    ThreadHostState hostState,
  ) {
    final openId = hostState.openThreadId;
    if (openId == null) return null;
    return _resolveThreadRow(threadsState, openId);
  }

  Future<void> _applyThreadsResolution({
    required ThreadsState threadsState,
    required bool isSplit,
  }) async {
    if (!threadsState.isSuccess || _didApplyThreadsResolution) return;
    // Wait until the ops|room split is actually shown. Threads can succeed
    // before beacon content loads; burning the flag then leaves the 3rd
    // column spinning forever when split turns on later.
    if (!isSplit) return;
    _didApplyThreadsResolution = true;

    final host = context.read<ThreadHostCubit>();
    if (host.state.openThreadId != null) return;

    final row = _resolveAccessibleRow(threadsState, widget.threadId);
    if (row == null) return;

    await host.select(row);
    if (!mounted) return;

    final messageId = widget.messageId?.trim();
    if (messageId != null && messageId.isNotEmpty) {
      host.roomCubit?.prepareThreadScroll(
        messageId: messageId,
        coordinationItemId: row.item?.id,
      );
    }
    unawaited(_syncExpandedThreadQuery(row.threadId));
  }

  Future<void> _openThread(
    RequestThread thread, {
    required bool isSplit,
    String? messageId,
  }) async {
    if (!isSplit) {
      await context.router.push(
        ThreadDetailRoute(
          threadId: thread.threadId,
          messageId: messageId,
        ),
      );
      return;
    }

    final host = context.read<ThreadHostCubit>();
    await host.select(thread);
    if (!mounted) return;

    final scrollMessageId = messageId?.trim();
    if (scrollMessageId != null && scrollMessageId.isNotEmpty) {
      host.roomCubit?.prepareThreadScroll(
        messageId: scrollMessageId,
        coordinationItemId: thread.item?.id,
      );
    }
    unawaited(_syncExpandedThreadQuery(thread.threadId));
  }

  Future<void> _openGeneralThread({
    String? messageId,
    String? coordinationItemId,
  }) async {
    final threadsState = context.read<ThreadsCubit>().state;
    final row = threadsState.general ?? threadsState.firstAccessible;
    if (row == null) return;

    final isSplit = _usesExpandedThreadSplit(
      showBeaconContent:
          context.read<BeaconViewCubit>().state.beaconContentLoaded &&
          !context.read<BeaconViewCubit>().state.beaconUnavailable,
      threadsState: threadsState,
    );

    await _openThread(row, messageId: messageId, isSplit: isSplit);
    if (!mounted) return;

    final host = context.read<ThreadHostCubit>();
    final scrollMessageId = messageId?.trim();
    final itemId = coordinationItemId?.trim();
    if ((scrollMessageId != null && scrollMessageId.isNotEmpty) ||
        (itemId != null && itemId.isNotEmpty)) {
      host.roomCubit?.prepareThreadScroll(
        messageId: scrollMessageId,
        coordinationItemId: itemId,
      );
    }
  }

  void _onOpenCoordinationItemFromThread(CoordinationItem item) {
    if (planItemSuppressesItemDiscussion(item)) {
      context.read<ThreadHostCubit>().roomCubit?.prepareThreadScroll(
        messageId: item.threadAnchorMessageId,
        coordinationItemId: item.id,
      );
      return;
    }
    final row = _resolveThreadRow(
      context.read<ThreadsCubit>().state,
      item.id,
    );
    if (row == null) return;
    final threadsState = context.read<ThreadsCubit>().state;
    final isSplit = _usesExpandedThreadSplit(
      showBeaconContent:
          context.read<BeaconViewCubit>().state.beaconContentLoaded &&
          !context.read<BeaconViewCubit>().state.beaconUnavailable,
      threadsState: threadsState,
    );
    unawaited(_openThread(row, isSplit: isSplit));
  }

  void _refreshThreadsTab() {
    unawaited(context.read<ThreadsCubit>().fetch());
  }

  @override
  void initState() {
    super.initState();
    _tabIndex = _beaconViewTabIndex(widget.viewTab).clamp(
      0,
      kBeaconTabCount - 1,
    );
    _peopleTabAttentionActive =
        _beaconPeopleTabAttentionQueryTruthy(widget.peopleTabAttention) &&
        _tabIndex == kBeaconTabPeople;
  }

  @override
  void didUpdateWidget(BeaconViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _didApplyThreadsResolution = false;
      _focusThreadId = null;
      _focusUserId = null;
      _roomPaneWidthOverride = null;
    }
    if (oldWidget.viewTab != widget.viewTab) {
      _tabIndex = _beaconViewTabIndex(widget.viewTab).clamp(
        0,
        kBeaconTabCount - 1,
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    final windowClass = context.windowClass;
    final previous = _lastWindowClass;
    _lastWindowClass = windowClass;

    if (previous == null) return;
    if (previous == WindowClass.expanded &&
        windowClass != WindowClass.expanded) {
      final openThreadId = context.read<ThreadHostCubit>().state.openThreadId;
      if (openThreadId != null) {
        final host = context.read<ThreadHostCubit>();
        host.scheduleWindowClassTransition(() {
          if (!mounted) return;
          if (context.router.currentChild?.name == ThreadDetailRoute.name) {
            return;
          }
          unawaited(
            context.router.push(
              ThreadDetailRoute(threadId: openThreadId),
            ),
          );
        });
      }
    }
  }

  void _switchToTab(int tab) {
    if (tab < 0 || tab >= kBeaconTabCount) return;
    setState(() {
      if (_tabIndex == kBeaconTabPeople && tab != kBeaconTabPeople) {
        _peopleTabAttentionActive = false;
      }
      _tabIndex = tab;
      _bannerMessage = null;
      _focusThreadId = null;
      _focusUserId = null;
    });
  }

  void _activatePeopleTabAttention() {
    setState(() {
      _tabIndex = kBeaconTabPeople;
      _peopleTabAttentionActive = true;
      _bannerMessage = null;
      _focusThreadId = null;
      _focusUserId = null;
    });
  }

  void _focusThreadByItemId(String itemId) {
    setState(() {
      _tabIndex = kBeaconTabThreads;
      _focusThreadId = itemId;
      _focusUserId = null;
      _bannerMessage = null;
      _peopleTabAttentionActive = false;
    });
  }

  void _onTapCoordinationLogEvent(BeaconActivityEvent e) {
    final kind = e.coordinationKind;
    final itemId = e.coordinationItemId?.trim();

    if (kind == CoordinationItemKind.ask ||
        kind == CoordinationItemKind.promise ||
        kind == CoordinationItemKind.blocker) {
      if (itemId != null && itemId.isNotEmpty) {
        setState(() {
          _tabIndex = kBeaconTabThreads;
          _focusThreadId = itemId;
          _focusUserId = null;
          _bannerMessage = null;
          _peopleTabAttentionActive = false;
        });
      }
      return;
    }

    if (kind == CoordinationItemKind.plan) {
      setState(() {
        _tabIndex = kBeaconTabThreads;
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
        _tabIndex = kBeaconTabPeople;
        _focusUserId = userId;
        _focusThreadId = null;
        _bannerMessage = null;
        _peopleTabAttentionActive = false;
      });
    }
  }

  void _clearOperationalFocus() {
    if (_focusThreadId == null && _focusUserId == null) return;
    setState(() {
      _focusThreadId = null;
      _focusUserId = null;
    });
  }

  Widget _buildOperationalBody({
    required BeaconViewCubit beaconViewCubit,
    required ScreenCubit screenCubit,
    required BeaconViewState beaconState,
    required bool isSplit,
    required void Function(RequestThread thread) onOpenThread,
  }) {
    return TenturaContentColumn(
      child: BeaconOperationalScrollView(
        beaconViewCubit: beaconViewCubit,
        screenCubit: screenCubit,
        tabIndex: _tabIndex,
        onTabChanged: _switchToTab,
        peopleTabAttentionActive: _peopleTabAttentionActive,
        onPeopleTabAttentionCleared: () => setState(() {
          _peopleTabAttentionActive = false;
        }),
        onActivatePeopleTabAttention: _activatePeopleTabAttention,
        onFocusCoordinationItem: (item) => _focusThreadByItemId(item.id),
        focusThreadId: _focusThreadId,
        focusUserId: _focusUserId,
        onOperationalFocusCleared: _clearOperationalFocus,
        onTapCoordinationLogEvent: _onTapCoordinationLogEvent,
        onOpenThread: onOpenThread,
        onOpenGeneralThread: () => unawaited(_openGeneralThread()),
        onThreadsTabRefresh: _refreshThreadsTab,
        selectedThreadId: isSplit
            ? context.watch<ThreadHostCubit>().state.openThreadId
            : null,
        beaconState: beaconState,
      ),
    );
  }

  Widget _buildThreadDetailPane({
    required BeaconViewState beaconState,
    required ThreadsState threadsState,
    required ThreadHostState hostState,
  }) {
    if (hostState.switching) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    final thread = _selectedThread(threadsState, hostState);
    if (thread == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return ThreadDetail(
      thread: thread,
      beaconAuthorId: beaconState.beacon.author.id,
      onCoordinationSaved: _refreshThreadsTab,
      onOpenCoordinationItem: _onOpenCoordinationItemFromThread,
    );
  }

  Widget _splitThreadPaneAppBar({
    required ThreadsState threadsState,
    required ThreadHostState hostState,
    required BeaconViewState beaconState,
    required L10n l10n,
    required Widget overflow,
  }) {
    final thread = _selectedThread(threadsState, hostState);
    if (thread == null) {
      return Align(
        alignment: Alignment.centerRight,
        child: overflow,
      );
    }

    final Widget title;
    if (thread.isGeneral) {
      title = ThreadDetailGeneralTitle(
        title: threadGeneralAppBarTitle(l10n, beaconState.beacon),
        beacon: beaconState.beacon,
        involvedProfiles: beaconState.activeHelpOfferUsers,
        currentUserId: beaconState.myProfile.id,
      );
    } else if (thread.item != null) {
      title = ThreadDetailTitle(
        fallback: threadTitleFallback(l10n, thread),
        item: thread.item!,
      );
    } else {
      return Align(
        alignment: Alignment.centerRight,
        child: overflow,
      );
    }

    return Row(
      children: [
        Expanded(child: title),
        overflow,
      ],
    );
  }

  Widget _buildExpandedSplitBody({
    required BeaconViewState beaconState,
    required BeaconViewCubit beaconViewCubit,
    required ScreenCubit screenCubit,
    required ThreadsState threadsState,
    required ThreadHostState hostState,
    required TenturaTokens tt,
    required void Function(RequestThread thread) onOpenThread,
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
              child: _buildOperationalBody(
                beaconViewCubit: beaconViewCubit,
                screenCubit: screenCubit,
                beaconState: beaconState,
                isSplit: true,
                onOpenThread: onOpenThread,
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
              child: _buildThreadDetailPane(
                beaconState: beaconState,
                threadsState: threadsState,
                hostState: hostState,
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final beaconViewCubit = context.read<BeaconViewCubit>();
    final l10n = L10n.of(context)!;

    return MultiBlocListener(
      listeners: [
        BlocListener<ThreadsCubit, ThreadsState>(
          listenWhen: (p, c) => !p.isSuccess && c.isSuccess,
          listener: (context, threadsState) {
            final beaconState = beaconViewCubit.state;
            final showBeaconContent =
                beaconState.beaconContentLoaded &&
                !beaconState.beaconUnavailable;
            final isSplit = _usesExpandedThreadSplit(
              showBeaconContent: showBeaconContent,
              threadsState: threadsState,
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
                      // The outer window can be expanded while this route is
                      // hosted in a narrower content pane. Do not mount the
                      // two-pane room view unless that parent can hold both
                      // of its minimum-width panes.
                      const minPaneWidth = 360.0;
                      const splitHandleWidth = TenturaSpacing.row;
                      final isSplit =
                          constraints.maxWidth >=
                              minPaneWidth * 2 + splitHandleWidth &&
                          _usesExpandedThreadSplit(
                            showBeaconContent: showBeaconContent,
                            threadsState: threadsState,
                          );

                      void onOpenThread(RequestThread thread) {
                        unawaited(() async {
                          await _openThread(
                            thread,
                            isSplit: isSplit,
                          );
                        }());
                      }

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
                          onOpenThread: onOpenThread,
                        );
                      } else {
                        body = _buildOperationalBody(
                          beaconViewCubit: beaconViewCubit,
                          screenCubit: screenCubit,
                          beaconState: state,
                          isSplit: false,
                          onOpenThread: onOpenThread,
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

                      // Do not wrap in PopScope(canPop: false) while a
                      // ThreadDetail child is open: on Flutter Web that
                      // installs a history sentinel on the still-mounted
                      // operational route and can make the next AppBar back
                      // (request → My Desk) a no-op. ThreadDetailScreen owns
                      // its own PopScope for chat exit.
                      return Scaffold(
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
                          title: isSplit
                              ? const SizedBox.shrink()
                              : BeaconViewAppBarTitle(
                                  beacon: state.beacon,
                                  showBeaconContent: showBeaconContent,
                                  phaseStatus: appBarPhaseStatus,
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
                                      inRoomSurface: false,
                                      roomCubit: null,
                                      onItemsTabRefresh: _refreshThreadsTab,
                                      onAuthorManageStatus: () async {
                                        await beaconViewCubit
                                            .refreshReviewWindowInfo();
                                        if (!context.mounted) return;
                                        await showBeaconViewUpdateStatusSheet(
                                          context,
                                          beaconViewCubit.state,
                                          beaconViewCubit,
                                          onOpenPeopleTab: () => _switchToTab(
                                            kBeaconTabPeople,
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
                                    final overflow = showBeaconContent
                                        ? beaconViewAppBarOverflow(
                                            context: context,
                                            state: state,
                                            cubit: beaconViewCubit,
                                            screenCubit: screenCubit,
                                            l10n: l10n,
                                            inRoomSurface: false,
                                            roomCubit: null,
                                            onItemsTabRefresh:
                                                _refreshThreadsTab,
                                            onAuthorManageStatus: () async {
                                              await beaconViewCubit
                                                  .refreshReviewWindowInfo();
                                              if (!context.mounted) return;
                                              await showBeaconViewUpdateStatusSheet(
                                                context,
                                                beaconViewCubit.state,
                                                beaconViewCubit,
                                                onOpenPeopleTab: () =>
                                                    _switchToTab(
                                                      kBeaconTabPeople,
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
                                            overflow: overflow,
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
                            kBeaconEntryRoomNotification => HomeTabSpec.forTab(
                              HomeTab.updates,
                            ).index,
                            _ => HomeTabSpec.forTab(HomeTab.work).index,
                          },
                          child: SafeArea(child: contentColumn),
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
