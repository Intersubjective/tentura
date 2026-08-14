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
import 'package:tentura/features/coordination_item/ui/bloc/item_actions_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/presenter/beacon_phase_presenter.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../widget/beacon_anchor_status.dart';
import '../widget/beacon_operational_scroll_view.dart';
import '../widget/beacon_view_app_bar_overflow.dart';
import '../widget/beacon_view_app_bar_title.dart';
import '../widget/beacon_view_forward_app_bar_button.dart';
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
}) =>
    windowClass == WindowClass.expanded &&
    showBeaconContent &&
    hasThreadRows;

double beaconViewRoomSplitPaneWidth(
  TenturaTokens tt, {
  double? availableWidth,
  double minPaneWidth = 360.0,
}) {
  const maxPaneWidth = 640.0;
  var effectiveMaxPaneWidth = maxPaneWidth;
  if (availableWidth != null && availableWidth.isFinite) {
    final minOperationalWidth = math.max(
      minPaneWidth,
      (tt.contentMaxWidth ?? tt.chatColumnMaxWidth) / 2,
    );
    effectiveMaxPaneWidth = math.max(
      minPaneWidth,
      math.min(maxPaneWidth, availableWidth - minOperationalWidth),
    );
  }
  return tt.chatColumnMaxWidth.clamp(minPaneWidth, effectiveMaxPaneWidth);
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
    this.embedded = false,
    this.onEmbeddedLeave,
    this.onRequestThreadRoute,
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

  /// Hosted inside another screen (e.g. Inbox master–detail). Skips Scaffold /
  /// TenturaTopBar / route URL thread lifecycle; thread detail is pane-local.
  final bool embedded;

  /// Called from embedded error "go back" — host may clear selection.
  final VoidCallback? onEmbeddedLeave;

  /// Embedded narrow pane: host pushes canonical thread detail URL.
  final void Function(String threadId, String? messageId)? onRequestThreadRoute;

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

  void _leaveBeaconView(BuildContext context) {
    if (widget.embedded) {
      widget.onEmbeddedLeave?.call();
      return;
    }
    final router = context.router;
    if (router.canPop()) {
      unawaited(router.maybePop());
      return;
    }
    unawaited(router.root.replacePath(kPathMyWork));
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
    bool relativeToTabBranch = false,
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
    final pathPrefix = relativeToTabBranch
        ? kPathBeaconView.replaceFirst('/', '')
        : kPathBeaconView;
    final base = '$pathPrefix/${widget.id}';
    if (q.isEmpty) return base;
    return '$base?${Uri(queryParameters: q).query}';
  }

  Future<void> _syncExpandedThreadQuery(String? threadId) {
    if (widget.embedded) return Future<void>.value();
    return context.router.replacePath(
      _beaconViewPath(
        viewTab: kBeaconViewTabThreads,
        threadId: threadId,
        relativeToTabBranch: true,
      ),
    );
  }

  bool _hasThreadDetailChild() {
    if (widget.embedded) return false;
    return context.router.currentChild?.name == ThreadDetailRoute.name;
  }

  bool _usesExpandedThreadSplit({
    required bool showBeaconContent,
    required ThreadsState threadsState,
    required double? detailWidth,
  }) {
    final hasThreadRows =
        threadsState.isSuccess && threadsState.threads.isNotEmpty;
    if (!showBeaconContent || !hasThreadRows) return false;
    if (widget.embedded) {
      if (detailWidth == null) return false;
      return myWorkDetailFitsOpsRoom(detailWidth, tight: true);
    }
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
    _didApplyThreadsResolution = true;
    if (!isSplit) return;

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
    if (!widget.embedded) {
      unawaited(_syncExpandedThreadQuery(row.threadId));
    }
  }

  Future<void> _openThread(
    RequestThread thread, {
    required bool isSplit,
    String? messageId,
  }) async {
    if (!isSplit) {
      if (widget.embedded) {
        widget.onRequestThreadRoute?.call(thread.threadId, messageId);
        return;
      }
      unawaited(
        context.router.push(
          ThreadDetailRoute(
            threadId: thread.threadId,
            messageId: messageId,
          ),
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
    if (!widget.embedded) {
      unawaited(_syncExpandedThreadQuery(thread.threadId));
    }
  }

  Future<void> _openGeneralThread({
    String? messageId,
    String? coordinationItemId,
  }) async {
    final threadsState = context.read<ThreadsCubit>().state;
    final row = threadsState.general ?? threadsState.firstAccessible;
    if (row == null) return;

    final isSplit = _usesExpandedThreadSplit(
      showBeaconContent: context.read<BeaconViewCubit>().state.beaconContentLoaded &&
          !context.read<BeaconViewCubit>().state.beaconUnavailable,
      threadsState: threadsState,
      detailWidth: null,
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
      detailWidth: null,
    );
    unawaited(_openThread(row, isSplit: isSplit));
  }

  Future<void> _closeSplitThread() async {
    await context.read<ThreadHostCubit>().clear();
    if (!mounted) return;
    if (!widget.embedded) {
      unawaited(_syncExpandedThreadQuery(null));
    }
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
    if (widget.embedded) return;

    final windowClass = context.windowClass;
    final previous = _lastWindowClass;
    _lastWindowClass = windowClass;

    if (previous == null) return;
    if (previous == WindowClass.expanded && windowClass != WindowClass.expanded) {
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

  Widget _buildGeneralSplitChrome({
    required BeaconViewState state,
    required L10n l10n,
    required VoidCallback onBack,
  }) {
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final title = state.beacon.title.isEmpty
        ? l10n.beaconViewTitle
        : state.beacon.title;

    return Material(
      color: scheme.surface,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(color: scheme.outlineVariant),
          ),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: tt.tightGap,
            vertical: tt.tightGap,
          ),
          child: Row(
            children: [
              Semantics(
                label: l10n.beaconRoomBackToChat,
                button: true,
                child: IconButton(
                  tooltip: l10n.beaconRoomBackToChat,
                  onPressed: onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildThreadDetailPane({
    required BeaconViewState beaconState,
    required ThreadsState threadsState,
    required ThreadHostState hostState,
    required L10n l10n,
  }) {
    if (hostState.switching) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    final thread = _selectedThread(threadsState, hostState);
    if (thread == null) {
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    final detail = ThreadDetail(
      thread: thread,
      beaconAuthorId: beaconState.beacon.author.id,
      onCoordinationSaved: _refreshThreadsTab,
      onOpenCoordinationItem: _onOpenCoordinationItemFromThread,
    );

    final paneBody = Expanded(child: detail);

    if (thread.item == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildGeneralSplitChrome(
            state: beaconState,
            l10n: l10n,
            onBack: () => unawaited(_closeSplitThread()),
          ),
          paneBody,
        ],
      );
    }

    return BlocProvider(
      key: ValueKey('item-actions-${thread.threadId}'),
      create: (_) => ItemActionsCubit(item: thread.item!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ThreadDetailColumnChrome(
            onBack: () => unawaited(_closeSplitThread()),
          ),
          paneBody,
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
    required void Function(RequestThread thread) onOpenThread,
    bool useTightPaneWidths = false,
  }) {
    final minPane = useTightPaneWidths ? 280.0 : 360.0;
    final l10n = L10n.of(context)!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final threadPaneWidth = beaconViewRoomSplitPaneWidth(
          tt,
          availableWidth: constraints.maxWidth,
          minPaneWidth: minPane,
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
            const TenturaVerticalHairline(),
            SizedBox(
              width: threadPaneWidth,
              child: _buildThreadDetailPane(
                beaconState: beaconState,
                threadsState: threadsState,
                hostState: hostState,
                l10n: l10n,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildEmbeddedPaneHeader({
    required BuildContext context,
    required BeaconViewState state,
    required BeaconViewCubit beaconViewCubit,
    required ScreenCubit screenCubit,
    required L10n l10n,
    required bool showBeaconContent,
    required bool showInitialLoading,
    required BeaconPhaseStatusPresentation appBarPhaseStatus,
  }) {
    final tt = context.tt;
    return Material(
      color: tt.surface,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tt.tightGap,
          vertical: tt.tightGap,
        ),
        child: Row(
          children: [
            Expanded(
              child: BeaconViewAppBarTitle(
                beacon: state.beacon,
                showBeaconContent: showBeaconContent,
                phaseStatus: appBarPhaseStatus,
                l10n: l10n,
              ),
            ),
            if (beaconViewShowsForwardAppBarAction(
                  state: state,
                  showBeaconContent: showBeaconContent,
                  showInitialLoading: showInitialLoading,
                ))
              BeaconViewForwardAppBarButton(
                onPressed: () => unawaited(
                  beaconViewOpenForwardThenMaybeNudgeOfferHelp(
                    context,
                    beaconViewCubit,
                    l10n,
                  ),
                ),
              ),
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
                  await beaconViewCubit.refreshReviewWindowInfo();
                  if (!context.mounted) return;
                  await showBeaconViewUpdateStatusSheet(
                    context,
                    beaconViewCubit.state,
                    beaconViewCubit,
                    onOpenPeopleTab: () => _switchToTab(kBeaconTabPeople),
                    onOpenGeneralThread: () => unawaited(_openGeneralThread()),
                  );
                },
              ),
          ],
        ),
      ),
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
            final detailWidth = widget.embedded
                ? MediaQuery.sizeOf(context).width
                : null;
            final isSplit = _usesExpandedThreadSplit(
              showBeaconContent: showBeaconContent,
              threadsState: threadsState,
              detailWidth: detailWidth,
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
            p.coordinationDeniesRoomAdmission != c.coordinationDeniesRoomAdmission,
        builder: (context, state) {
          return BlocBuilder<ThreadsCubit, ThreadsState>(
            buildWhen: (p, c) =>
                p.status != c.status || p.threads != c.threads,
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

                  void onOpenThread(RequestThread thread) {
                    unawaited(() async {
                      final width = widget.embedded
                          ? MediaQuery.sizeOf(context).width
                          : null;
                      final isSplit = _usesExpandedThreadSplit(
                        showBeaconContent: showBeaconContent,
                        threadsState: threadsState,
                        detailWidth: width,
                      );
                      await _openThread(thread, isSplit: isSplit);
                    }());
                  }

                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final detailWidth = constraints.maxWidth;
                      final isSplit = _usesExpandedThreadSplit(
                        showBeaconContent: showBeaconContent,
                        threadsState: threadsState,
                        detailWidth: detailWidth,
                      );

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
                      final useTightPaneWidths = widget.embedded;

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
                          useTightPaneWidths: useTightPaneWidths,
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

                      if (widget.embedded) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _buildEmbeddedPaneHeader(
                              context: context,
                              state: state,
                              beaconViewCubit: beaconViewCubit,
                              screenCubit: screenCubit,
                              l10n: l10n,
                              showBeaconContent: showBeaconContent,
                              showInitialLoading: showInitialLoading,
                              appBarPhaseStatus: appBarPhaseStatus,
                            ),
                            if (state.isLoading)
                              LinearProgressIndicator(
                                minHeight: 2,
                                backgroundColor:
                                    scheme.surfaceContainerHighest,
                              ),
                            Expanded(child: contentColumn),
                          ],
                        );
                      }

                      final onDetailChild = _hasThreadDetailChild();
                      return PopScope(
                        canPop: !onDetailChild,
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
                                    onFallback: () =>
                                        _leaveBeaconView(context),
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
                                    if (beaconViewShowsForwardAppBarAction(
                                          state: state,
                                          showBeaconContent:
                                              showBeaconContent,
                                          showInitialLoading:
                                              showInitialLoading,
                                        ))
                                      BeaconViewForwardAppBarButton(
                                        onPressed: () => unawaited(
                                          beaconViewOpenForwardThenMaybeNudgeOfferHelp(
                                            context,
                                            beaconViewCubit,
                                            l10n,
                                          ),
                                        ),
                                      ),
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
                                      final threadPaneWidth =
                                          beaconViewRoomSplitPaneWidth(
                                        tt,
                                        availableWidth: constraints.maxWidth,
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
                                      final showSplitForward =
                                          beaconViewShowsForwardAppBarAction(
                                            state: state,
                                            showBeaconContent:
                                                showBeaconContent,
                                            showInitialLoading:
                                                showInitialLoading,
                                          );
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
                                          SizedBox(
                                            width: threadPaneWidth,
                                            child: Align(
                                              alignment: Alignment.centerRight,
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  if (showSplitForward)
                                                    BeaconViewForwardAppBarButton(
                                                      onPressed: () =>
                                                          unawaited(
                                                        beaconViewOpenForwardThenMaybeNudgeOfferHelp(
                                                          context,
                                                          beaconViewCubit,
                                                          l10n,
                                                        ),
                                                      ),
                                                    ),
                                                  overflow,
                                                ],
                                              ),
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
                          body: SafeArea(child: contentColumn),
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
