import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/widget/home_rail_frame.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/entity/room_composer_intent.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/beacon_hierarchy_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/threads_state.dart';
import 'package:tentura/features/beacon_threads/ui/coordination_room_navigation.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/beacon/beacon_room_lease.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_request_modes.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_plan_people.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_plan/ui/bloc/plan_cubit.dart';
import 'package:tentura/features/beacon_plan/ui/widget/beacon_plan_surface.dart';
import 'package:tentura/features/beacon_plan/ui/widget/beacon_plan_page.dart';
import 'package:tentura/ui/beacon/beacon_room_navigation_scope.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/first_load_gate.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../widget/beacon_activity_sheet.dart';
import '../widget/beacon_anchor_status.dart';
import 'package:tentura/ui/widget/beacon_involved_people_face_pile.dart';

import '../widget/beacon_now_surface.dart';
import '../widget/beacon_people_surface.dart';
import '../widget/beacon_room_surface.dart';
import '../widget/beacon_showcase_surface.dart';
import '../widget/beacon_surface_tabs.dart';
import '../widget/beacon_view_app_bar_overflow.dart';
import '../widget/beacon_view_app_bar_title.dart';
import '../widget/beacon_view_status_bottom_sheet.dart';
import 'package:tentura/ui/beacon/beacon_surface.dart';

bool _beaconPeopleTabAttentionQueryTruthy(String? v) {
  if (v == null || v.isEmpty) return false;
  final s = v.toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

/// Expanded thread split when the list has rows — not gated on room navigation.
bool beaconViewUsesExpandedThreadSplit({
  required WindowClass windowClass,
  required bool showBeaconContent,
  required bool hasThreadRows,
}) => windowClass == WindowClass.expanded && showBeaconContent && hasThreadRows;

/// Width of the Now pane (the supporting pane) in a chat|Now split.
///
/// The chat is the primary pane and takes the rest; Material 3 supporting
/// panes sit trailing at a fixed width. Pass [preferredWidth] to honor a user
/// drag; otherwise 40% of [availableWidth], kept between
/// [kBeaconSplitNowPaneMinDefaultWidth] and
/// [kBeaconSplitNowPaneMaxDefaultWidth]. Always leaves at least
/// [minPaneWidth] for the chat when space allows; when both floors cannot fit,
/// the chat shrinks first so Now's scroll view keeps a readable width (it
/// crashes at ~100px cross-axis extents).
double beaconViewNowSplitPaneWidth(
  TenturaTokens tt, {
  double? availableWidth,
  double minPaneWidth = 360.0,
  double? preferredWidth,
}) {
  if (availableWidth == null || !availableWidth.isFinite) {
    return math.max(minPaneWidth, preferredWidth ?? minPaneWidth);
  }

  // When both floors cannot fit, Now keeps its floor and the chat shrinks.
  final floor = math.min(minPaneWidth, availableWidth);
  final maxForNow = math.max(floor, availableWidth - minPaneWidth);
  final ideal =
      preferredWidth ??
      (availableWidth * 0.4).clamp(
        math.max(minPaneWidth, kBeaconSplitNowPaneMinDefaultWidth),
        kBeaconSplitNowPaneMaxDefaultWidth,
      );
  return ideal.clamp(floor, maxForNow);
}

/// Narrowest default for the Now pane; its cards need room for two-column
/// rows (team member + next move, help offers).
const double kBeaconSplitNowPaneMinDefaultWidth = 400;

/// Widest the Now pane gets on its own; a drag can widen it further.
const double kBeaconSplitNowPaneMaxDefaultWidth = 640;

/// The Now pane width the person dragged to, for the rest of the session.
double? _sessionNowPaneWidth;

/// Forgets the dragged Now pane width (tests start from the default).
@visibleForTesting
void resetBeaconSplitNowPaneWidth() => _sessionNowPaneWidth = null;

/// The split header over the chat pane; it spans exactly that pane (#169).
const beaconSplitChatHeaderKey = Key('beacon-split-chat-header');

class BeaconViewScreen extends StatefulWidget {
  const BeaconViewScreen({
    this.id = '',
    this.isDeepLink,
    this.viewTab,
    this.peopleTabAttention,
    this.entry,
    this.threadId,
    this.messageId,
    this.syncRoute = true,
    this.stepId,
    this.planPage,
    this.planRevision,
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

  /// False when embedded in a pane: surface changes must not replace the host
  /// route's path.
  final bool syncRoute;

  /// Plan step whose card opens once the plan loads (`tab=plan&step=`).
  final String? stepId;

  /// Page open over the plan (`tab=plan&page=history|edit`).
  final String? planPage;

  /// With `page=history`: the revision to open (`rev=`).
  final String? planRevision;

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

  /// User drag override for the Now pane width; null = default. Kept for the
  /// session, so every Request opens at the width the person chose.
  double? get _nowPaneWidthOverride => _sessionNowPaneWidth;
  set _nowPaneWidthOverride(double? value) => _sessionNowPaneWidth = value;

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

  /// Author previewing the showcase ("How others see it").
  bool _previewAsOutsider = false;

  /// The Request plan (#220) was asked to load once (the host's [PlanCubit]).
  bool _planLoadRequested = false;

  /// The deep-linked plan step ([BeaconViewScreen.stepId]) was opened once.
  bool _planStepHandled = false;

  /// A leave from an empty Plan surface is scheduled (#546).
  bool _leavePlanScheduled = false;

  /// The open plan page was opened from here (a browser history entry of
  /// ours), so closing it goes back rather than replacing the URL.
  bool _planPageOpenedHere = false;

  /// Loads the plan once the viewer is known to be inside the Request;
  /// outsiders (showcase, admission pending) never fetch it.
  void _maybeLoadPlan(PlanCubit? cubit, {required bool insider}) {
    if (cubit == null || !insider || _planLoadRequested) return;
    _planLoadRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !cubit.isClosed) unawaited(cubit.load());
    });
  }

  bool _isShowcase(BeaconViewState state) =>
      state.beaconContentLoaded &&
      !state.beaconUnavailable &&
      beaconViewModeFor(
            state,
            previewAsOutsider: _previewAsOutsider && state.isBeaconMine,
          ) ==
          BeaconViewMode.showcase;

  void _setPreviewAsOutsider(bool value) {
    if (_previewAsOutsider == value) return;
    setState(() {
      _previewAsOutsider = value;
      _bannerMessage = null;
      if (value) _selectedSurface = BeaconSurface.now;
    });
  }

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

    // A child Request opened from its parent (#154): when the stack cannot
    // pop (e.g. after close/complete), return to the parent Request detail
    // instead of dropping to the home tab root list.
    final lineageParentId = context
        .read<BeaconViewCubit>()
        .state
        .beacon
        .lineageParentBeaconId;
    if (lineageParentId != null && lineageParentId.isNotEmpty) {
      unawaited(router.root.replacePath('$kPathBeaconView/$lineageParentId'));
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
    BeaconPlanPage? planPage,
    int? planRevision,
  }) {
    final q = <String, String>{};
    if (viewTab != null && viewTab.isNotEmpty) {
      q[kQueryBeaconViewTab] = viewTab;
    }
    if (planPage != null) {
      q[kQueryPlanPage] = planPage.queryValue;
      if (planRevision != null) q[kQueryPlanRevision] = '$planRevision';
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
    if (!widget.syncRoute) return Future<void>.value();
    return _replaceBeaconPath(
      _beaconViewPath(
        viewTab: beaconSurfaceViewTab(surface),
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

  /// Rewrites this Request's URL in place: same page, no new browser entry.
  /// `replacePath` cannot do it (from this screen's own router the absolute
  /// path does not resolve), so navigate the root router and report the
  /// URL change as a replace ([Router.neglect]).
  Future<void> _replaceBeaconPath(String path) {
    final root = context.router.root;
    // No [Router] (a bare widget host): no browser entry to protect.
    if (Router.maybeOf(context) == null) return root.navigatePath(path);
    late Future<void> done;
    Router.neglect(context, () => done = root.navigatePath(path));
    return done;
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
    // The side pane keeps a Plan / People tab the URL asked for; the URL
    // names the chat thread only when the pane is on NOW.
    if (_selectedSurface == BeaconSurface.plan ||
        _selectedSurface == BeaconSurface.people) {
      return;
    }
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
        _switchToSurface(BeaconSurface.now);
      } else if (!isSplit && previous) {
        _switchToSurface(BeaconSurface.room);
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
    _selectedSurface = beaconViewSurfaceForTab(widget.viewTab);
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
      _planLoadRequested = false;
      _didApplyThreadsResolution = false;
      _focusThreadId = null;
      _focusUserId = null;
      _hadThreadRowsAtLeastOnce = false;
      _lastIsSplit = null;
      _didOpenActivitySheetForLogTab = false;
      _previewAsOutsider = false;
    }
    if (oldWidget.stepId != widget.stepId || oldWidget.id != widget.id) {
      _planStepHandled = false;
    }
    if (oldWidget.planPage != null && widget.planPage == null) {
      _planPageOpenedHere = false;
    }
    if (oldWidget.viewTab != widget.viewTab) {
      _selectedSurface = beaconViewSurfaceForTab(widget.viewTab);
      if (widget.viewTab == 'log') {
        _maybeOpenActivitySheetForLogTab();
      }
    }
  }

  /// The page open over the plan, if the Plan tab is showing.
  BeaconPlanPage? get _activePlanPage => _selectedSurface == BeaconSurface.plan
      ? BeaconPlanPage.tryParse(widget.planPage)
      : null;

  /// Plan history / editor: a pushed URL (a browser history entry), so the
  /// back gesture closes the page instead of leaving the Request.
  void _openPlanPage(BeaconPlanPage page, {int? revision}) {
    _planPageOpenedHere = true;
    // The URL may lag the tab shown, so do not count on a `tab=` change.
    _switchToSurface(BeaconSurface.plan, syncQuery: false);
    // Root router: this screen's own router cannot resolve the absolute path.
    unawaited(
      context.router.root.navigatePath(
        _beaconViewPath(
          viewTab: kBeaconViewTabPlan,
          planPage: page,
          planRevision: revision,
        ),
      ),
    );
  }

  void _closePlanPage() {
    if (_planPageOpenedHere && context.router.canNavigateBack) {
      _planPageOpenedHere = false;
      context.router.back();
      return;
    }
    // Deep link or reload onto the page: nothing of ours to go back to.
    unawaited(
      _replaceBeaconPath(_beaconViewPath(viewTab: kBeaconViewTabPlan)),
    );
  }

  Widget _buildPlanPage(BeaconPlanPage page, BeaconViewState beaconState) =>
      BeaconPlanPageView(
        key: ValueKey('plan-page-${page.name}-${beaconState.beacon.id}'),
        page: page,
        beaconId: beaconState.beacon.id,
        admitted: beaconPlanAdmittedPeople(beaconState),
        revision: int.tryParse(widget.planRevision ?? ''),
        onClose: _closePlanPage,
      );

  /// The Home tab whose rail item this Request is under.
  HomeTab get _railTab => switch (widget.entry) {
    kBeaconEntryInbox => HomeTab.inbox,
    kBeaconEntryRoomNotification => HomeTab.updates,
    _ => HomeTab.work,
  };

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

  /// «Не успеваю → написать в обсуждении» (#220): opens the discussion with
  /// the step quoted in the composer; sending that message records the
  /// «can't make it» with the person's words.
  void _startPlanCantMakeChat(PlanStep step, bool isSplit) {
    final plan = context.read<PlanCubit?>()?.state.plan;
    final intent = RoomComposerIntent(
      prefill: L10n.of(
        context,
      )!.planCantMakeChatPrefill(step.index, step.title),
      planCantMake: plan == null
          ? null
          : PlanCantMakeInChat(
              stepId: step.id,
              baseRevisionSeq: plan.revisionSeq,
            ),
    );
    context.read<ThreadHostCubit>().armComposerIntent(intent);
    if (isSplit) {
      unawaited(_openGeneralThread());
    } else {
      _focusDiscussionGeneral();
    }
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

  /// The surface actually shown for [_selectedSurface] (#546): the Plan
  /// surface needs a plan with a step (or one still loading, or a plan page
  /// being opened over it); otherwise the default surface stands in.
  BeaconSurface _shownSurface(PlanState? planState) {
    if (_selectedSurface != BeaconSurface.plan) return _selectedSurface;
    if (_planPageOpenedHere ||
        BeaconPlanPage.tryParse(widget.planPage) != null) {
      return BeaconSurface.plan;
    }
    if (planState != null &&
        beaconPlanSurfaceAvailable(
          plan: planState.plan,
          loading: planState.isLoading,
        )) {
      return BeaconSurface.plan;
    }
    return BeaconSurface.now;
  }

  /// A Plan surface without a plan (a `tab=plan` link, the last step
  /// removed): go to the default surface and say so in the URL (#546).
  void _leaveEmptyPlanSurface() {
    if (_leavePlanScheduled) return;
    _leavePlanScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _leavePlanScheduled = false;
      if (!mounted || _selectedSurface != BeaconSurface.plan) return;
      if (_shownSurface(context.read<PlanCubit?>()?.state) ==
          BeaconSurface.plan) {
        return;
      }
      _switchToSurface(BeaconSurface.now);
    });
  }

  Widget _buildTabRow({
    required bool isSplit,
    required TenturaTokens tt,
    required BeaconSurface shownSurface,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(bottom: BorderSide(color: tt.borderSubtle)),
      ),
      // Edge to edge, like a Material tab bar (#609): on a 360 dp phone the
      // screen padding left a quarter too narrow for «Обсуждение», and the
      // whole row fell back to icons only.
      child: BeaconSurfaceTabs(
        isSplit: isSplit,
        selectedSurface: shownSurface,
        onSurfaceSelected: _switchToSurface,
        onSurfaceReselected: _onSurfaceReselected,
        peopleTabAttentionActive: _peopleTabAttentionActive,
      ),
    );
  }

  Widget _buildSelectedSurface({
    required BeaconViewCubit beaconViewCubit,
    required ScreenCubit screenCubit,
    required BeaconViewState beaconState,
    required bool isSplit,
    required BeaconRoomLease roomLease,
    required BeaconSurface shownSurface,
  }) {
    final surface = isSplit && shownSurface == BeaconSurface.room
        ? BeaconSurface.now
        : shownSurface;

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
          onPlanCantMakeChat: (step) => _startPlanCantMakeChat(step, isSplit),
        );
      case BeaconSurface.plan:
        return BeaconPlanSurface(
          key: ValueKey('plan-${beaconState.beacon.id}'),
          beaconId: beaconState.beacon.id,
          viewerId: beaconState.myProfile.id,
          admitted: beaconPlanAdmittedPeople(beaconState),
          // In the split the chat is always on screen; otherwise go there.
          onOpenDiscussion: isSplit ? null : _focusDiscussionGeneral,
          onCantMakeChat: (step) => _startPlanCantMakeChat(step, isSplit),
          initialStepId: _planStepHandled ? null : widget.stepId,
          onInitialStepHandled: () => _planStepHandled = true,
        );
      case BeaconSurface.room:
        return BeaconRoomSurface(
          key: ValueKey('room-$_threadsFoldEpoch'),
          host: beaconViewCubit,
          roomLease: roomLease,
          legacyThreadId: widget.threadId,
          messageId: _roomScrollMessageId ?? widget.messageId,
          coordinationItemId: _roomScrollCoordinationItemId,
          onCoordinationSaved: _refreshThreadsTab,
          onOpenCoordinationItem: _onOpenCoordinationItemFromThread,
          closureHadNoFinalCheck:
              beaconState.closureState?.hadNoFinalCheck,
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
    Widget content(PlanState? planState) {
      final shownSurface = _shownSurface(planState);
      if (shownSurface != _selectedSurface) _leaveEmptyPlanSurface();
      return TenturaContentColumn(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildTabRow(
              isSplit: isSplit,
              tt: context.tt,
              shownSurface: shownSurface,
            ),
            Expanded(
              child: _buildSelectedSurface(
                beaconViewCubit: beaconViewCubit,
                screenCubit: screenCubit,
                beaconState: beaconState,
                isSplit: isSplit,
                roomLease: roomLease,
                shownSurface: shownSurface,
              ),
            ),
          ],
        ),
      );
    }

    final planCubit = context.read<PlanCubit?>();
    if (planCubit == null) return content(null);
    // Rebuilt only when the plan comes or goes (#546), not on every tick.
    return BlocBuilder<PlanCubit, PlanState>(
      bloc: planCubit,
      buildWhen: (p, c) =>
          (p.plan?.isEmpty, p.isLoading) != (c.plan?.isEmpty, c.isLoading),
      builder: (context, planState) => content(planState),
    );
  }

  /// Now pane width for the chat|Now split. The app bar row and the body
  /// both pass their post-rail width so header and pane share one budget.
  double _splitNowPaneWidth(
    TenturaTokens tt,
    double maxWidth, {
    double? preferredWidth,
  }) => beaconViewNowSplitPaneWidth(
    tt,
    availableWidth: maxWidth - TenturaSpacing.row,
    preferredWidth: preferredWidth ?? _nowPaneWidthOverride,
  );

  /// Wide windows: the chat is the primary pane in the middle, Now (with
  /// People) the supporting pane on the trailing side.
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
        final nowPaneWidth = _splitNowPaneWidth(tt, constraints.maxWidth);
        // Tab walks the chat pane (messages, then the composer) before the
        // Now pane, not row by row across both panes (#415).
        return FocusTraversalGroup(
          policy: OrderedTraversalPolicy(),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(1),
                  child: FocusTraversalGroup(
                    child: BeaconRoomSurface(
                      host: beaconViewCubit,
                      roomLease: roomLease,
                      legacyThreadId: widget.threadId,
                      messageId: widget.messageId,
                      onCoordinationSaved: _refreshThreadsTab,
                      onOpenCoordinationItem: _onOpenCoordinationItemFromThread,
                      closureHadNoFinalCheck:
                          beaconState.closureState?.hadNoFinalCheck,
                    ),
                  ),
                ),
              ),
              TenturaVerticalResizeHandle(
                onDragDelta: (dx) {
                  // Now pane is on the trailing side: drag left (negative dx)
                  // widens it. Several moves can land before the next frame, so
                  // each one starts from the width the previous one set, not
                  // from the width this frame was built with.
                  setState(() {
                    _nowPaneWidthOverride = _splitNowPaneWidth(
                      tt,
                      constraints.maxWidth,
                      preferredWidth:
                          (_nowPaneWidthOverride ?? nowPaneWidth) - dx,
                    );
                  });
                },
              ),
              SizedBox(
                width: nowPaneWidth,
                // The pane's own messenger: its bars ("Plan saved" and the
                // like) span this pane only and never cover the chat composer
                // beside it (#448). It wraps the whole switch so a bar shown
                // as a plan page closes outlives that page.
                child: FocusTraversalOrder(
                  order: const NumericFocusOrder(2),
                  child: FocusTraversalGroup(
                    child: PaneScaffoldMessenger(
                      child: Scaffold(
                        primary: false,
                        backgroundColor: Colors.transparent,
                        resizeToAvoidBottomInset: false,
                        // A plan page takes the plan's pane; the chat stays beside
                        // it.
                        body: switch (_activePlanPage) {
                          final page? => _buildPlanPage(page, beaconState),
                          null => _buildTabbedContent(
                            beaconViewCubit: beaconViewCubit,
                            screenCubit: screenCubit,
                            beaconState: beaconState,
                            isSplit: true,
                            roomLease: roomLease,
                          ),
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Header over the Now pane: who is involved (tap opens People) and the
  /// one ⋮ for the whole split (#168).
  Widget _splitNowPaneAppBar({
    required BeaconViewState beaconState,
    required bool showBeaconContent,
    required L10n l10n,
    required TenturaTokens tt,
    required Widget overflow,
  }) {
    void openPeople() => _switchToSurface(BeaconSurface.people);
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(horizontal: tt.screenHPadding),
      child: Row(
        children: [
          Expanded(
            child: showBeaconContent
                ? Align(
                    alignment: AlignmentDirectional.centerStart,
                    // The pile's own label ("3 people, 2 online") is merged
                    // into the People button's (U093 review).
                    child: MergeSemantics(
                      child: Semantics(
                        button: true,
                        label: l10n.beaconHudPeopleRowSemantics,
                        onTap: openPeople,
                        child: BeaconInvolvedPeopleFacePile(
                          beacon: beaconState.beacon,
                          involvedProfiles:
                              beaconState.beacon.admittedHelperUsers,
                          currentUserId: beaconState.myProfile.id,
                          helperCount: beaconState.beacon.admittedHelperCount,
                          onTap: openPeople,
                          // U093: BeaconViewCubit watches the team's presence.
                          showPresence: true,
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
          overflow,
        ],
      ),
    );
  }

  Widget _buildAppBarTitle({
    required bool isSplit,
    required bool showStatus,
    required BeaconViewState state,
    required bool showBeaconContent,
    required L10n l10n,
  }) {
    if (isSplit) return const SizedBox.shrink();

    // #492: one header on every tab (Chat included): title + status line.
    // The involved people live on the People tab.
    return BeaconViewAppBarTitle(
      beacon: state.beacon,
      showBeaconContent: showBeaconContent,
      showStatus: showStatus,
      phaseStatus: beaconViewStatusSlots(l10n, state).presentation,
      l10n: l10n,
    );
  }

  @override
  Widget build(BuildContext context) => BeaconPlanPageScope(
    open: _openPlanPage,
    child: Builder(builder: _buildScreen),
  );

  Widget _buildScreen(BuildContext context) {
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
                  final beaconPending =
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
                      final showcase = _isShowcase(state);
                      final isSplit =
                          !showcase &&
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
                      // All status chrome shares the body gate's reveal flag.
                      var gateTheBody = false;

                      Widget body;
                      if (showInitialUnavailable) {
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
                      } else {
                        final Widget content;
                        if (beaconPending) {
                          content = const SizedBox.shrink();
                        } else if (showcase) {
                          // Outsiders get no tab row: nothing to switch to
                          // until the author lets them in (#159, #104).
                          content = TenturaContentColumn(
                            child: BeaconShowcaseSurface(
                              beaconViewCubit: beaconViewCubit,
                              screenCubit: screenCubit,
                              isPreview: _previewAsOutsider,
                            ),
                          );
                        } else if (isSplit) {
                          content = _buildExpandedSplitBody(
                            beaconState: state,
                            beaconViewCubit: beaconViewCubit,
                            screenCubit: screenCubit,
                            threadsState: threadsState,
                            hostState: hostState,
                            tt: tt,
                            roomLease: roomLease,
                          );
                        } else {
                          content = _buildTabbedContent(
                            beaconViewCubit: beaconViewCubit,
                            screenCubit: screenCubit,
                            beaconState: state,
                            isSplit: false,
                            roomLease: roomLease,
                          );
                        }
                        // The room is primary content wherever it is shown
                        // and opens; the gate keeps it mounted so it loads
                        // meanwhile. The gate wraps the scaffold below so the
                        // bar can read the same reveal as the body (#545).
                        gateTheBody = true;
                        body = content;
                      }

                      _maybeLoadPlan(
                        context.read<PlanCubit?>(),
                        insider:
                            showBeaconContent &&
                            !showcase &&
                            !state.isRoomAdmissionBlocked,
                      );

                      // Narrow windows: a plan page is a screen of its own,
                      // with its own top bar and back.
                      final planPage = _activePlanPage;
                      if (planPage != null &&
                          !isSplit &&
                          !showcase &&
                          showBeaconContent) {
                        return HomeRailFrame(
                          selectedTab: _railTab,
                          child: _buildPlanPage(planPage, state),
                        );
                      }

                      Widget screenFrame({
                        required Widget frameBody,
                        required bool phaseStatusVisible,
                      }) {
                        // A status too long for the title's line goes under
                        // the bar row (#486). On a phone that line stays out
                        // until the body gate reveals, so it and the body
                        // appear in one frame (#545). The split header does
                        // not use this slot.
                        final statusBottom =
                            showcase || isSplit || !phaseStatusVisible
                            ? null
                            : BeaconViewStatusBottom.maybeOf(
                                context,
                                appBarPhaseStatus,
                              );
                        final contentColumn = Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (showcase && _previewAsOutsider)
                              MaterialBanner(
                                content: Text(l10n.beaconPreviewBanner),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        _setPreviewAsOutsider(false),
                                    child: Text(l10n.beaconPreviewExit),
                                  ),
                                ],
                              ),
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
                            Expanded(child: frameBody),
                          ],
                        );

                        // Keep canPop true on NOW so the plain "leave the request"
                        // path never goes through a blocking PopScope (Flutter Web
                        // history sentinel on canPop:false made AppBar back a no-op
                        // when a ThreadDetail child was open — that child route goes
                        // away in U10, but the leave path must stay unblocked).
                        return BeaconRoomNavigationScope(
                          isRoomPresented:
                              !showcase &&
                              isBeaconRoomPresented(
                                isSplit: isSplit,
                                selectedSurface: _selectedSurface,
                              ),
                          roomLease: roomLease,
                          openGeneralAnchor: _openGeneralThread,
                          child: PopScope(
                            canPop:
                                (showcase && !_previewAsOutsider) ||
                                (!showcase &&
                                    _selectedSurface == BeaconSurface.now),
                            onPopInvokedWithResult: (didPop, result) {
                              if (didPop) return;
                              // An open plan page handles the back itself.
                              if (_activePlanPage != null) return;
                              if (showcase) {
                                _setPreviewAsOutsider(false);
                                return;
                              }
                              if (_selectedSurface == BeaconSurface.room ||
                                  _selectedSurface == BeaconSurface.plan ||
                                  _selectedSurface == BeaconSurface.people) {
                                _switchToSurface(BeaconSurface.now);
                              }
                            },
                            child: HomeRailFrame(
                              selectedTab: _railTab,
                              child: Scaffold(
                                appBar: TenturaTopBar.of(
                                  context,
                                  bottom: statusBottom,
                                  alignment: isSplit
                                      ? TenturaTopBarAlignment.edgeToEdge
                                      : TenturaTopBarAlignment.content,
                                  leading: isSplit
                                      ? null
                                      : AutoLeadingWithFallback(
                                          fallbackPath: kPathMyWork,
                                          onFallback: () =>
                                              _leaveBeaconView(context),
                                        ),
                                  // The showcase carries the title under its
                                  // cover; the bar keeps only back and ⋮.
                                  title: showcase
                                      ? const SizedBox.shrink()
                                      : _buildAppBarTitle(
                                          isSplit: isSplit,
                                          showStatus:
                                              statusBottom == null &&
                                              phaseStatusVisible,
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
                                                  !showcase &&
                                                  _selectedSurface ==
                                                      BeaconSurface.room,
                                              onPreviewAsOthers:
                                                  showcase ||
                                                      !state.isBeaconMine
                                                  ? null
                                                  : () => _setPreviewAsOutsider(
                                                      true,
                                                    ),
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
                                                    .refreshClosureState();
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
                                            ),
                                        ],
                                  row: isSplit
                                      ? LayoutBuilder(
                                          builder: (context, constraints) {
                                            const handleWidth =
                                                TenturaSpacing.row;
                                            // Same post-rail width as the body
                                            // split, so panes line up (#169).
                                            final nowPaneWidth =
                                                _splitNowPaneWidth(
                                                  tt,
                                                  constraints.maxWidth,
                                                );
                                            // #168: one ⋮ for the whole split
                                            // header — request management and
                                            // discussion actions share it.
                                            final splitOverflow =
                                                showBeaconContent
                                                ? beaconViewAppBarOverflow(
                                                    context: context,
                                                    state: state,
                                                    cubit: beaconViewCubit,
                                                    screenCubit: screenCubit,
                                                    l10n: l10n,
                                                    inRoomSurface: true,
                                                    combineSplitPanes: true,
                                                    onPreviewAsOthers:
                                                        state.isBeaconMine
                                                        ? () =>
                                                              _setPreviewAsOutsider(
                                                                true,
                                                              )
                                                        : null,
                                                    roomCubit: context
                                                        .read<ThreadHostCubit>()
                                                        .roomCubit,
                                                    onItemsTabRefresh:
                                                        _refreshThreadsTab,
                                                    onActivityLog: () =>
                                                        unawaited(
                                                          _openActivitySheet(),
                                                        ),
                                                    onAuthorManageStatus: () async {
                                                      await beaconViewCubit
                                                          .refreshClosureState();
                                                      if (!context.mounted)
                                                        return;
                                                      await showBeaconViewUpdateStatusSheet(
                                                        context,
                                                        beaconViewCubit.state,
                                                        beaconViewCubit,
                                                        onOpenPeopleTab: () =>
                                                            _switchToSurface(
                                                              BeaconSurface
                                                                  .people,
                                                            ),
                                                        onOpenGeneralThread:
                                                            () => unawaited(
                                                              _openGeneralThread(),
                                                            ),
                                                      );
                                                    },
                                                  )
                                                : const SizedBox.shrink();
                                            return Row(
                                              children: [
                                                // Over the chat: the Request
                                                // itself — title and status —
                                                // so its state never lives only
                                                // in the side pane.
                                                Expanded(
                                                  child: Padding(
                                                    key:
                                                        beaconSplitChatHeaderKey,
                                                    padding:
                                                        EdgeInsetsDirectional.symmetric(
                                                          horizontal:
                                                              tt.screenHPadding,
                                                        ),
                                                    child: Row(
                                                      children: [
                                                        AutoLeadingWithFallback(
                                                          fallbackPath:
                                                              kPathMyWork,
                                                          onFallback: () =>
                                                              _leaveBeaconView(
                                                                context,
                                                              ),
                                                        ),
                                                        Expanded(
                                                          child: BeaconViewAppBarTitle(
                                                            beacon:
                                                                state.beacon,
                                                            showBeaconContent:
                                                                showBeaconContent,
                                                            showStatus:
                                                                phaseStatusVisible,
                                                            phaseStatus:
                                                                appBarPhaseStatus,
                                                            l10n: l10n,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(
                                                  width: handleWidth,
                                                ),
                                                SizedBox(
                                                  width: nowPaneWidth,
                                                  child: _splitNowPaneAppBar(
                                                    beaconState: state,
                                                    showBeaconContent:
                                                        showBeaconContent &&
                                                        phaseStatusVisible,
                                                    l10n: l10n,
                                                    tt: tt,
                                                    overflow: splitOverflow,
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
                            ),
                          ),
                        );
                      }

                      if (!gateTheBody) {
                        return screenFrame(
                          frameBody: body,
                          phaseStatusVisible: true,
                        );
                      }

                      // Same ready / revealOnTimeout the gate has always used.
                      // frameBuilder reads the gate's own revealed flag, so the
                      // status and face pile cannot drift from the body.
                      final roomExpected =
                          !showcase &&
                          !state.isRoomAdmissionBlocked &&
                          !_isLegacyThreadId(widget.threadId) &&
                          !(threadsState.isSuccess &&
                              _generalThread(threadsState) == null) &&
                          isBeaconRoomPresented(
                            isSplit: isSplit,
                            selectedSurface: _selectedSurface,
                          );
                      final room = context.read<ThreadHostCubit>().roomCubit;
                      return StreamBuilder<void>(
                        stream: room?.stream,
                        builder: (context, _) =>
                            BlocBuilder<
                              BeaconHierarchyCubit,
                              BeaconHierarchyState
                            >(
                              builder: (context, hierarchy) =>
                                  TenturaFirstLoadGate(
                                    // Timeout may reveal other partial data,
                                    // but child/forward reads must finish first.
                                    revealOnTimeout:
                                        !hierarchy.isLoading &&
                                        !state.forwardsLoading,
                                    ready:
                                        state.firstLoadDone &&
                                        (room?.state.firstLoadDone ??
                                            !roomExpected) &&
                                        (showcase ||
                                            (!isSplit &&
                                                _selectedSurface !=
                                                    BeaconSurface.now) ||
                                            (!hierarchy.isLoading &&
                                                (hierarchy.hasCapabilities ||
                                                    hierarchy
                                                            .capabilitiesError !=
                                                        null))),
                                    onRetry: () => unawaited(
                                      beaconViewCubit.retryInitialLoad(),
                                    ),
                                    frameBuilder: (_, revealed, gated) =>
                                        screenFrame(
                                          frameBody: gated,
                                          phaseStatusVisible: revealed,
                                        ),
                                    child: body,
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
