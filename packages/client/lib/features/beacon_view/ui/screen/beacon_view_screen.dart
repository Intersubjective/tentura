import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/coordination_room_navigation.dart';
import 'package:tentura/features/beacon_view/domain/beacon_view_entry_source.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_cubit.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_view_app_bar_title.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';

import '../bloc/beacon_view_cubit.dart';
import '../widget/beacon_anchor_status.dart';
import '../widget/beacon_operational_scroll_view.dart';
import '../widget/beacon_view_app_bar_overflow.dart';
import '../widget/beacon_view_status_bottom_sheet.dart';
import '../widget/beacon_view_constants.dart';
import '../widget/beacon_view_room_app_bar_button.dart';

bool _beaconPeopleTabAttentionQueryTruthy(String? v) {
  if (v == null || v.isEmpty) return false;
  final s = v.toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

/// Operational tab indices: items(0), people(1), log(2). Room is a separate surface.

/// Query [kQueryBeaconViewTab]: `items` | `people` | `log` (+ legacy aliases).
/// Room opens via `tab=room` or [kQueryBeaconSurface]=room, not as a segment tab.
int _beaconViewTabIndex(String? viewTab) {
  switch (viewTab) {
    case 'items':
      return kBeaconTabItems;
    case 'people':
    case 'helpOffers':
    case 'help_offers':
      return kBeaconTabPeople;
    case 'log':
    case 'activity':
    case 'timeline':
      return kBeaconTabLog;
    case 'details':
    case 'forwards':
    case 'overview':
    default:
      return kBeaconTabItems;
  }
}

bool beaconViewUsesExpandedRoomSplit({
  required WindowClass windowClass,
  required bool showBeaconContent,
  required bool canNavigateBeaconRoom,
}) =>
    windowClass == WindowClass.expanded &&
    showBeaconContent &&
    canNavigateBeaconRoom;

/// Single source of truth for "does the current route say room is open".
/// Derived fresh from route params every time — no stored flag mirrors it.
/// Legacy (compact/regular) room-surface visibility and the split focus/URL
/// side effects both read this instead of tracking their own copy.
bool beaconViewRoomRequestedByRoute({
  required String? surface,
  required String? viewTab,
  required String? isDeepLink,
  required String? entry,
}) {
  final legacySurface = surface?.trim().toLowerCase();
  return legacySurface == kBeaconSurfaceRoomQueryValue ||
      viewTab == 'room' ||
      normalizeBeaconViewEntry(
            isDeepLink: isDeepLink,
            rawFromQuery: BeaconViewEntrySourceWire.parseQuery(entry),
          ) ==
          BeaconViewEntrySource.roomNotification;
}

/// Compact/regular room-surface visibility: the route must request room
/// *and* access must currently be allowed. Folding [canNavigateBeaconRoom] in
/// here (rather than re-checking it at each call site) keeps app-bar chrome,
/// `PopScope`, and body selection consistent — previously a denied-mid-flight
/// room could show a "room" title/back-button while the body had already
/// fallen back to operational.
bool beaconViewShowsLegacyRoomSurface({
  required bool isSplit,
  required bool roomRequestedByRoute,
  required bool canNavigateBeaconRoom,
}) => !isSplit && roomRequestedByRoute && canNavigateBeaconRoom;

double beaconViewRoomSplitPaneWidth(
  TenturaTokens tt, {
  double? availableWidth,
}) {
  const minPaneWidth = 360.0;
  const maxPaneWidth = 560.0;
  var effectiveMaxPaneWidth = maxPaneWidth;
  if (availableWidth != null && availableWidth.isFinite) {
    final minOperationalWidth =
        (tt.contentMaxWidth ?? tt.chatColumnMaxWidth) / 2;
    effectiveMaxPaneWidth = math.max(
      minPaneWidth,
      math.min(maxPaneWidth, availableWidth - minOperationalWidth),
    );
  }
  return tt.chatColumnMaxWidth.clamp(minPaneWidth, effectiveMaxPaneWidth);
}

@RoutePage()
class BeaconViewScreen extends StatefulWidget implements AutoRouteWrapper {
  const BeaconViewScreen({
    @PathParam('id') this.id = '',
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    @QueryParam(kQueryBeaconViewTab) this.viewTab,
    @QueryParam(kQueryBeaconPeopleTabAttention) this.peopleTabAttention,
    @QueryParam(kQueryBeaconSurface) this.surface,
    @QueryParam(kQueryBeaconEntry) this.entry,
    @QueryParam(kQueryCoordinationItemId) this.coordinationItemId,
    super.key,
  });

  final String id;

  final String? isDeepLink;

  /// `items` | `people` | `log` (+ legacy aliases). Room: `tab=room` or [surface]=room.
  final String? viewTab;

  /// With [viewTab]=`people`, truthy values pulse/highlight the People tab until interaction.
  final String? peopleTabAttention;

  /// `room` opens full-screen room; `status` is the default operational view.
  final String? surface;

  /// Entry provenance ([kQueryBeaconEntry]).
  final String? entry;

  /// Open room focused on this coordination item (notification deep link).
  final String? coordinationItemId;

  @override
  Widget wrappedRoute(_) => localScreenCubitScope(
    child: BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (previous, current) =>
          previous.profile.id != current.profile.id,
      builder: (context, profileState) {
        final myProfile = profileState.profile;
        return BlocProvider(
          key: ValueKey('BeaconViewCubit:$id:${myProfile.id}'),
          create: (_) => BeaconViewCubit(
            myProfile: myProfile,
            id: id,
          ),
          child: this,
        );
      },
    ),
  );

  @override
  State<BeaconViewScreen> createState() => _BeaconViewScreenState();
}

class _BeaconViewScreenState extends State<BeaconViewScreen> {
  late int _tabIndex;
  late bool _peopleTabAttentionActive;

  /// Coordination item / participant to scroll-to + flash after a Log row tap.
  String? _focusItemId;
  String? _focusUserId;

  RoomCubit? _roomCubit;
  ItemsTabCubit? _itemsTabCubit;
  bool _didApplyFetchResolution = false;
  String? _bannerMessage;

  /// Reentrancy guard: [_exitRoomSurface] can be invoked from `PopScope` more
  /// than once in quick succession (e.g. a rapid double-tap on the app-bar
  /// back button before the first pop attempt resolves); not derivable from
  /// route/window state (it's about an in-flight *action*, not "what is
  /// currently displayed").
  bool _roomExitInProgress = false;

  /// Ensures mark-seen on the previous visit finishes before re-open refresh;
  /// an in-flight async handle, not something route/window state can derive.
  Future<void>? _pendingRoomExit;
  bool _splitRoomRouteSyncScheduled = false;
  bool _splitRoomRouteFocusPostFrameScheduled = false;
  String? _splitRoomRouteFocusKey;

  void _unfocusForRouteChange() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _leaveBeaconView(BuildContext context) {
    final router = context.router;
    if (router.canPop()) {
      // Not `back()`: on web that's `window.history.back()`, an async
      // browser-level round-trip — see [_exitRoomSurface]. `maybePop` drives
      // the StackRouter's own page list directly and synchronously.
      unawaited(router.maybePop());
      return;
    }
    // Nothing below this page in *this* tab branch (e.g. a cold-loaded deep
    // link) — replace on root with the absolute path. Not `router.replacePath`
    // (this branch's own nested StackRouter): an absolute, leading-slash path
    // never matches this branch's own relative registrations, so scope
    // resolution falls through unpredictably — see [_stripRoomFromUrl].
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

  bool _roomFromRouteParams(BeaconViewScreen w) =>
      beaconViewRoomRequestedByRoute(
        surface: w.surface,
        viewTab: w.viewTab,
        isDeepLink: w.isDeepLink,
        entry: w.entry,
      );

  /// Whether the router stack shows another page for *this same beacon*
  /// directly beneath the current (room) page — i.e. room was entered by
  /// [_enterRoomSurface] pushing an overlay onto an already-open operational
  /// page, as opposed to a cold/deep-link load that baked `?tab=room` into
  /// the only page for this beacon. Exit must pop in the former case
  /// (`StackRouter.back`) and strip the query in place in the latter
  /// (`replacePath` would otherwise leave a duplicate beacon-view page and
  /// force two pops to leave the beacon).
  ///
  /// Deliberately *not* a stored per-State flag: `_enterRoomSurface` would
  /// have to set it on the *operational* instance right before pushing, but
  /// the *new* State created for the pushed room page starts with its own,
  /// unset copy of any such flag — so a stored flag can never be read back
  /// correctly by the page that actually needs to act on it on exit. The
  /// stack is owned by the (single, shared) StackRouter, not by either
  /// page's State, so it survives the push intact.
  bool _hasOperationalBeaconPageBeneath() {
    final stack = context.router.stack;
    if (stack.length < 2) return false;
    final below = stack[stack.length - 2];
    return below.name == BeaconViewRoute.name &&
        below.routeData.pathParams.optString('id') == widget.id;
  }

  /// [relativeToTabBranch]: drop the leading `/` so the path matches the
  /// *nested* `beacon/view/:id` registration under this tab branch
  /// (`browseDetailChildren()` in home_tab_branches.dart) directly, scoped to
  /// `context.router` (this branch's own StackRouter) rather than falling
  /// through to root's standalone `/beacon/view/:id` redirect-target entry —
  /// segment-matching requires an exact leading-slash match, so a leading `/`
  /// fails against the branch's own (slash-less) registered pattern and the
  /// scope search falls through to root instead. See [_stripRoomFromUrl].
  String _beaconViewPath({
    String? viewTab,
    bool stripRoomEntry = false,
    bool relativeToTabBranch = false,
  }) {
    final q = <String, String>{};
    if (viewTab != null && viewTab.isNotEmpty) {
      q[kQueryBeaconViewTab] = viewTab;
    }
    final entry = widget.entry?.trim();
    final entryOpensRoom =
        normalizeBeaconViewEntry(
          isDeepLink: widget.isDeepLink,
          rawFromQuery: BeaconViewEntrySourceWire.parseQuery(widget.entry),
        ) ==
        BeaconViewEntrySource.roomNotification;
    if (entry != null &&
        entry.isNotEmpty &&
        !(stripRoomEntry && entryOpensRoom)) {
      q[kQueryBeaconEntry] = entry;
    }
    final pathPrefix = relativeToTabBranch
        ? kPathBeaconView.replaceFirst('/', '')
        : kPathBeaconView;
    final base = '$pathPrefix/${widget.id}';
    if (q.isEmpty) return base;
    return '$base?${Uri(queryParameters: q).query}';
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
  void didChangeDependencies() {
    super.didChangeDependencies();
    _releaseRoomCubitIfNoLongerNeeded();
  }

  /// Drops the embedded room cubit after [RoomCubit.close] flushes mark-seen.
  Future<void> _releaseEmbeddedRoomCubit() async {
    final c = _roomCubit;
    if (c == null) return;
    _roomCubit = null;
    if (!c.isClosed) {
      await c.close();
    }
  }

  @override
  void didUpdateWidget(BeaconViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _roomExitInProgress = false;
      _splitRoomRouteFocusKey = null;
    }
    final wasRoom = _roomFromRouteParams(oldWidget);
    final isRoom = _roomFromRouteParams(widget);
    if (isRoom &&
        _usesExpandedRoomSplitForState(
          context.read<BeaconViewCubit>().state,
        )) {
      _activateExpandedRoomSplit(fromRoute: true);
      return;
    }
    if (wasRoom && !isRoom) {
      // Route dropped room (e.g. our own `_stripRoomFromUrl` landed, or a
      // browser/forward-back sync) — reconcile the cubit; idempotent if
      // something else already released it.
      _exitRoomSurface(fromRouteSync: true);
    } else if (!wasRoom && isRoom) {
      // URL moved to ?tab=room while room was closed — treat this as an entry
      // signal and clear any stale exit-in-progress flag for the same reason
      // as in _enterRoomSurface above. Idempotent if room is already showing.
      _roomExitInProgress = false;
      _applyRoomSurfaceState(open: true);
    }
  }

  void _refreshItemsTab() {
    _itemsTabCubit ??= ItemsTabCubit(beaconId: widget.id);
    unawaited(_itemsTabCubit!.fetch());
  }

  @override
  void dispose() {
    unawaited(_releaseEmbeddedRoomCubit());
    unawaited(_itemsTabCubit?.close());
    super.dispose();
  }

  bool get _hasLiveRoomCubit {
    final c = _roomCubit;
    return c != null && !c.isClosed;
  }

  bool _usesExpandedRoomSplitForState(
    BeaconViewState s, {
    bool? showBeaconContent,
  }) => beaconViewUsesExpandedRoomSplit(
    windowClass: context.windowClass,
    showBeaconContent:
        showBeaconContent ?? (s.beaconContentLoaded && !s.beaconUnavailable),
    canNavigateBeaconRoom: s.canNavigateBeaconRoom,
  );

  /// Releases the embedded room cubit once neither the expanded split nor a
  /// route-level room request still needs it — e.g. after shrinking out of
  /// the split with no `?tab=room` left on the URL. Runs on every dependency
  /// change (window-class/resize is the main trigger). Comparing *current*
  /// need against *current* liveness is idempotent by construction, so no
  /// "was split last build" transition flag is required: if the route still
  /// asks for room, legacy rendering picks it up directly
  /// ([beaconViewShowsLegacyRoomSurface]) instead of forcing a release.
  void _releaseRoomCubitIfNoLongerNeeded() {
    if (!_hasLiveRoomCubit) return;
    final state = context.read<BeaconViewCubit>().state;
    if (_usesExpandedRoomSplitForState(state)) return;
    if (_roomFromRouteParams(widget) && state.canNavigateBeaconRoom) return;

    _roomExitInProgress = false;
    _pendingRoomExit = _exitRoomAndSyncUnread();
    unawaited(_pendingRoomExit);
  }

  void _prepareRoomPaneScroll([CoordinationItem? focusItem]) {
    final c = _roomCubit;
    if (c == null || c.isClosed) return;
    if (focusItem != null && focusItem.id.isNotEmpty) {
      c.prepareThreadScroll(
        messageId: focusItem.threadAnchorMessageId,
        coordinationItemId: focusItem.id,
      );
      return;
    }
    final itemId = widget.coordinationItemId?.trim();
    if (itemId != null && itemId.isNotEmpty) {
      c.prepareThreadScroll(coordinationItemId: itemId);
      return;
    }
    c.prepareThreadScroll();
  }

  void _scheduleExpandedRoomPaneRouteFocusIfNeeded() {
    if (_splitRoomRouteFocusPostFrameScheduled) return;
    _splitRoomRouteFocusPostFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _splitRoomRouteFocusPostFrameScheduled = false;
      if (!mounted) return;
      _focusExpandedRoomPaneFromRouteIfNeeded();
    });
  }

  void _focusExpandedRoomPaneFromRouteIfNeeded() {
    if (!_roomFromRouteParams(widget) && !_urlIndicatesRoom()) return;
    final focusKey = [
      widget.id,
      widget.viewTab ?? '',
      widget.surface ?? '',
      widget.entry ?? '',
      widget.coordinationItemId ?? '',
    ].join('|');
    if (_splitRoomRouteFocusKey == focusKey) return;
    _splitRoomRouteFocusKey = focusKey;
    _prepareRoomPaneScroll();
    _scheduleExpandedRoomRouteSync(
      popPushedRoom: _hasOperationalBeaconPageBeneath(),
    );
  }

  void _scheduleExpandedRoomRouteSync({bool popPushedRoom = false}) {
    if (_splitRoomRouteSyncScheduled) return;
    _splitRoomRouteSyncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _splitRoomRouteSyncScheduled = false;
        return;
      }
      _unfocusForRouteChange();
      if (popPushedRoom && context.router.canPop()) {
        // Not `StackRouter.back()`: on web that's `NavigationHistoryImpl`'s
        // literal `window.history.back()` — an async, browser-level
        // popstate round-trip whose reconciliation was observed to rewrite
        // *this* (top) page's own route data in place instead of removing
        // it, leaving a duplicate `BeaconViewRoute` in the stack. `maybePop`
        // drives the StackRouter's own page list directly (same mechanism
        // `AutoLeadingButton` uses), synchronously removing this page and
        // revealing the operational page beneath it.
        unawaited(context.router.maybePop());
        _splitRoomRouteSyncScheduled = false;
        return;
      }
      // Not `.whenComplete()`: `StackRouter.replacePath`'s returned Future
      // follows `push`'s "resolves when the pushed page is later popped"
      // contract, not "resolves when this navigation settles" — it would
      // never fire here, leaving this guard stuck forever. The actual
      // route/URL update already happens synchronously inside
      // `replacePath` (its guard chain is empty for this route), so it's
      // safe to clear the guard right after the call.
      unawaited(_stripRoomFromUrl(stripRoomEntry: true));
      _splitRoomRouteSyncScheduled = false;
    });
  }

  void _activateExpandedRoomSplit({
    CoordinationItem? focusItem,
    bool fromRoute = false,
    bool focusRoom = false,
  }) {
    final popPushedRoom = _hasOperationalBeaconPageBeneath();
    _roomExitInProgress = false;
    _ensureEmbeddedRoomCubit();
    if (focusRoom || fromRoute || focusItem != null) {
      _prepareRoomPaneScroll(focusItem);
    }
    if (fromRoute) {
      _scheduleExpandedRoomRouteSync(popPushedRoom: popPushedRoom);
    }
  }

  void _applyFetchResolution(BeaconViewState s) {
    if (!s.isSuccess || _didApplyFetchResolution) return;

    final roomRequested = _roomFromRouteParams(widget);
    final roomDenied =
        (roomRequested || _hasLiveRoomCubit) && !s.canNavigateBeaconRoom;
    if (roomDenied && (!s.beaconContextLoaded || s.myProfile.id.isEmpty)) {
      return;
    }

    setState(() {
      if (roomDenied) {
        // Rendering already falls back to operational once
        // `canNavigateBeaconRoom` is false (see
        // [beaconViewShowsLegacyRoomSurface]) — no local flag to clear here.
        if (s.showsRoomAccessUnavailableBanner) {
          _bannerMessage = L10n.of(
            context,
          )!.beaconViewRoomAccessUnavailableBanner;
        } else {
          unawaited(_stripRoomFromUrl());
        }
      }
      _didApplyFetchResolution = true;
      if (_usesExpandedRoomSplitForState(s)) {
        _activateExpandedRoomSplit(fromRoute: roomRequested);
      } else if (roomRequested && s.canNavigateBeaconRoom) {
        _ensureEmbeddedRoomCubit();
        final itemId = widget.coordinationItemId?.trim();
        if (itemId != null && itemId.isNotEmpty) {
          _roomCubit!.prepareThreadScroll(coordinationItemId: itemId);
        }
      }
    });
  }

  void _applyRoomSurfaceState({required bool open}) {
    if (open) {
      setState(_ensureEmbeddedRoomCubit);
      unawaited(_onRoomSurfaceOpened());
    } else {
      if (!_hasLiveRoomCubit) return;
      setState(() {});
      _pendingRoomExit = _exitRoomAndSyncUnread();
      unawaited(_pendingRoomExit);
    }
  }

  void _ensureEmbeddedRoomCubit() {
    if (_roomCubit != null && !_roomCubit!.isClosed) return;
    final initialAnchor = context.read<BeaconViewCubit>().roomReadThrough(
      widget.id,
    );
    _roomCubit = RoomCubit(
      beaconId: widget.id,
      initialUnreadAnchorAt: initialAnchor,
    );
  }

  /// In-room UI uses live [RoomCubit] unread; beacon shell uses server batch count.
  int _effectiveRoomUnreadCount(
    BeaconViewState beaconState, {
    required bool useLiveRoomCubit,
  }) {
    final rc = _roomCubit;
    if (useLiveRoomCubit && rc != null && !rc.isClosed) {
      return rc.state.unreadCount;
    }
    return beaconState.roomUnreadCount;
  }

  Future<void> _onRoomSurfaceOpened() async {
    final pending = _pendingRoomExit;
    if (pending != null) {
      await pending;
    }
    if (!mounted) return;
    if (mounted) setState(() {});
  }

  Future<void> _exitRoomAndSyncUnread() async {
    await _releaseEmbeddedRoomCubit();
    _pendingRoomExit = null;
    if (mounted) setState(() {});
  }

  bool _urlIndicatesRoom() {
    final url = context.router.currentUrl;
    return url.contains('$kQueryBeaconViewTab=room') ||
        url.contains('$kQueryBeaconSurface=room');
  }

  Future<void> _stripRoomFromUrl({bool stripRoomEntry = false}) {
    // Replace on *this tab branch's own* StackRouter (`context.router`, the
    // same one `_enterRoomSurface`'s `pushPath` already targets) with a path
    // relative to it (no leading `/`) — not `context.router.root.replacePath`
    // with the full `/home/<tab>/...` URL, and not a leading-slash path on
    // `context.router` either. `auto_route`'s segment matcher requires an
    // exact match: a leading `/` never matches this branch's own (slash-less)
    // `beacon/view/:id` registration, so scope resolution falls through to
    // root's *standalone* `/beacon/view/:id` redirect-target entry — whose
    // guard (`_forwardIntoHomeBranch` in root_router.dart) pushes a *second*
    // beacon-view page and/or rebuilds `HomeRoute` from scratch. The latter
    // forces `AutoTabsRouter`'s `TabsRouter.setupRoutes` to re-run with only
    // this one branch's children — and `setupRoutes` only consumes its
    // `pendingChildren` once, so the branch silently stops updating (URL and
    // body freeze while chrome briefly flashes the collapsed/no-detail
    // state). Same underlying fragility as `_shellSubtreeKey`'s comment in
    // home_screen.dart, triggered from a different call site. A relative path
    // matches this branch's own registration directly, keeping the replace a
    // single-level pop+push on this branch's own stack.
    return context.router.replacePath(
      _beaconViewPath(
        stripRoomEntry: stripRoomEntry,
        relativeToTabBranch: true,
      ),
    );
  }

  void _enterRoomSurface([CoordinationItem? focusItem]) {
    // Reset the exit-in-progress flag unconditionally on any user-initiated
    // entry.  The flag is set synchronously by _exitRoomSurface but cleared
    // only inside an async whenComplete callback (_stripRoomFromUrl).  If the
    // user re-enters before that callback fires (e.g. by quickly tapping the
    // chat icon after backing out), the flag stays true and the very next call
    // to _exitRoomSurface returns early, stranding the room open.
    _roomExitInProgress = false;
    if (!context.read<BeaconViewCubit>().state.canNavigateBeaconRoom) {
      return;
    }
    if (_usesExpandedRoomSplitForState(context.read<BeaconViewCubit>().state)) {
      setState(() {
        _activateExpandedRoomSplit(focusItem: focusItem, focusRoom: true);
      });
      return;
    }
    // Push a dedicated `?tab=room` route instead of also embedding room on the
    // route below — otherwise back pops the top route but leaves a live
    // [RoomCubit] on the underlying beacon view.
    if (!_roomFromRouteParams(widget)) {
      final roomPath = _beaconViewPath(viewTab: 'room');
      // Push so browser history retains the operational beacon URL; exit via
      // [StackRouter.back] (not replacePath) to avoid duplicate beacon entries.
      _unfocusForRouteChange();
      unawaited(context.router.pushPath(roomPath));
      return;
    }
    _applyRoomSurfaceState(open: true);
    final c = _roomCubit;
    if (c == null || c.isClosed) return;
    if (focusItem == null || focusItem.id.isEmpty) {
      c.prepareThreadScroll();
    } else {
      c.prepareThreadScroll(
        messageId: focusItem.threadAnchorMessageId,
        coordinationItemId: focusItem.id,
      );
    }
  }

  void _openItemDiscussion(CoordinationItem item) {
    if (item.kind == CoordinationItemKind.plan) {
      _enterRoomSurface(item);
      return;
    }
    unawaited(
      openCoordinationItemFromRoom(
        context,
        item: item,
        roomCubit: _roomCubit,
      ),
    );
  }

  void _exitRoomSurface({bool fromRouteSync = false}) {
    if (_roomExitInProgress) return;

    if (_usesExpandedRoomSplitForState(context.read<BeaconViewCubit>().state)) {
      _roomExitInProgress = false;
      if (_urlIndicatesRoom() || _roomFromRouteParams(widget)) {
        _scheduleExpandedRoomRouteSync();
      }
      return;
    }

    if (fromRouteSync) {
      if (_hasLiveRoomCubit) {
        _applyRoomSurfaceState(open: false);
      }
      return;
    }

    _roomExitInProgress = true;
    if (_hasLiveRoomCubit) {
      _applyRoomSurfaceState(open: false);
    }

    // Room opened via pushPath: pop the `?tab=room` history entry. Using
    // replacePath here duplicates `/beacon/view/:id` in the stack/history.
    //
    // Not `StackRouter.back()`: on web that's `NavigationHistoryImpl`'s
    // literal `window.history.back()` — an async, browser-level popstate
    // round-trip whose reconciliation was observed to rewrite *this* (top)
    // page's own route data in place instead of removing it, leaving a
    // duplicate `BeaconViewRoute` in the stack (the URL looked right — room
    // query stripped — but the page beneath was never actually revealed, so
    // a *second* back tap was needed to really leave).
    //
    // Not `maybePop()` either: we're here *because* this page's own
    // `PopScope.canPop` is false (that's what routed the system/AppBar back
    // gesture into this method instead of a plain pop), and `maybePop()`
    // consults that same `canPop` — it would just refuse, silently doing
    // nothing. `pop()` forces the StackRouter's own page list to drop this
    // page regardless of PopScope, synchronously revealing the operational
    // page beneath it.
    if (_hasOperationalBeaconPageBeneath()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _roomExitInProgress = false;
          return;
        }
        _unfocusForRouteChange();
        context.router.pop();
        _roomExitInProgress = false;
      });
      return;
    }

    // Deep link / notification entry at `?tab=room` — strip query in place.
    final needsUrlSync = _urlIndicatesRoom() || _roomFromRouteParams(widget);
    if (!needsUrlSync) {
      _roomExitInProgress = false;
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        _roomExitInProgress = false;
        return;
      }
      _unfocusForRouteChange();
      // Not `.whenComplete()`: see the comment on the sibling call in
      // `_scheduleExpandedRoomRouteSync` — `replacePath`'s Future resolves on
      // pop, not on navigation settling, so it would never fire here.
      unawaited(_stripRoomFromUrl());
      _roomExitInProgress = false;
    });
  }

  void _switchToTab(int tab) {
    if (tab < 0 || tab >= kBeaconTabCount) return;
    setState(() {
      _tabIndex = tab;
      _bannerMessage = null;
      _peopleTabAttentionActive = false;
      _focusItemId = null;
      _focusUserId = null;
    });
  }

  /// Log row tap → jump to the linked coordination item (Items tab) or, when the
  /// event has no item, to the related participant (People tab).
  void _onTapCoordinationLogEvent(BeaconActivityEvent e) {
    final itemId = e.coordinationItemId?.trim();
    if (itemId != null && itemId.isNotEmpty) {
      setState(() {
        _tabIndex = kBeaconTabItems;
        _focusItemId = itemId;
        _focusUserId = null;
        _bannerMessage = null;
        _peopleTabAttentionActive = false;
      });
      return;
    }
    final userId = (e.targetUserId ?? e.actorId)?.trim();
    if (userId != null && userId.isNotEmpty) {
      setState(() {
        _tabIndex = kBeaconTabPeople;
        _focusUserId = userId;
        _focusItemId = null;
        _bannerMessage = null;
        _peopleTabAttentionActive = false;
      });
    }
  }

  void _clearOperationalFocus() {
    if (_focusItemId == null && _focusUserId == null) return;
    setState(() {
      _focusItemId = null;
      _focusUserId = null;
    });
  }

  Widget _buildOperationalBody({
    required BeaconViewCubit beaconViewCubit,
    required ScreenCubit screenCubit,
  }) {
    if (_itemsTabCubit == null) {
      _itemsTabCubit = ItemsTabCubit(beaconId: widget.id);
      unawaited(_itemsTabCubit!.fetch());
    }
    return TenturaContentColumn(
      child: BlocProvider.value(
        value: _itemsTabCubit!,
        child: BeaconOperationalScrollView(
          beaconViewCubit: beaconViewCubit,
          screenCubit: screenCubit,
          tabIndex: _tabIndex,
          onTabChanged: _switchToTab,
          peopleTabAttentionActive: _peopleTabAttentionActive,
          onPeopleTabAttentionCleared: () => setState(() {
            _peopleTabAttentionActive = false;
          }),
          focusItemId: _focusItemId,
          focusUserId: _focusUserId,
          onOperationalFocusCleared: _clearOperationalFocus,
          onTapCoordinationLogEvent: _onTapCoordinationLogEvent,
          onEnterRoomSurface: _enterRoomSurface,
          onOpenItemDiscussion: _openItemDiscussion,
        ),
      ),
    );
  }

  Widget _buildRoomPane(BeaconViewState state) {
    final roomCubit = _roomCubit;
    return roomCubit == null || roomCubit.isClosed
        ? const Center(child: CircularProgressIndicator.adaptive())
        : BlocProvider.value(
            value: roomCubit,
            child: BlocListener<RoomCubit, RoomState>(
              listenWhen: (p, c) => p.unreadCount != c.unreadCount,
              listener: (ctx, roomState) {
                if (mounted) setState(() {});
              },
              child: BeaconRoomSurface(
                beaconAuthorId: state.beacon.author.id,
                onCoordinationSaved: _refreshItemsTab,
              ),
            ),
          );
  }

  Widget _buildExpandedSplitBody({
    required BeaconViewState state,
    required BeaconViewCubit beaconViewCubit,
    required ScreenCubit screenCubit,
    required TenturaTokens tt,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final roomPaneWidth = beaconViewRoomSplitPaneWidth(
          tt,
          availableWidth: constraints.maxWidth,
        );
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: _buildOperationalBody(
                beaconViewCubit: beaconViewCubit,
                screenCubit: screenCubit,
              ),
            ),
            const TenturaVerticalHairline(),
            SizedBox(
              width: roomPaneWidth,
              child: _buildRoomPane(state),
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
    return BlocListener<BeaconViewCubit, BeaconViewState>(
      listenWhen: (p, c) =>
          (!p.isSuccess && c.isSuccess) ||
          (_roomFromRouteParams(widget) &&
              !p.canNavigateBeaconRoom &&
              c.canNavigateBeaconRoom) ||
          ((_roomFromRouteParams(widget) || _hasLiveRoomCubit) &&
              p.canNavigateBeaconRoom &&
              !c.canNavigateBeaconRoom),
      listener: (ctx, s) {
        if (!s.isSuccess) return;
        if (!ctx.mounted) return;
        if ((_roomFromRouteParams(widget) || _hasLiveRoomCubit) &&
            !s.canNavigateBeaconRoom) {
          if (!s.beaconContextLoaded) return;
          if (s.myProfile.id.isEmpty) return;
          unawaited(_releaseEmbeddedRoomCubit());
          setState(() {
            // Rendering already falls back to operational once
            // `canNavigateBeaconRoom` is false — no local flag to clear here.
            if (s.showsRoomAccessUnavailableBanner) {
              _bannerMessage = L10n.of(
                ctx,
              )!.beaconViewRoomAccessUnavailableBanner;
            } else {
              unawaited(_stripRoomFromUrl());
            }
          });
          return;
        }
        _applyFetchResolution(s);
      },
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
            p.roomUnreadCount != c.roomUnreadCount ||
            p.canNavigateBeaconRoom != c.canNavigateBeaconRoom ||
            p.isRoomAdmissionBlocked != c.isRoomAdmissionBlocked ||
            p.coordinationDeniesRoomAdmission !=
                c.coordinationDeniesRoomAdmission,
        builder: (context, state) {
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

          final isSplit = beaconViewUsesExpandedRoomSplit(
            windowClass: context.windowClass,
            showBeaconContent: showBeaconContent,
            canNavigateBeaconRoom: state.canNavigateBeaconRoom,
          );
          if (isSplit) {
            _ensureEmbeddedRoomCubit();
            _scheduleExpandedRoomPaneRouteFocusIfNeeded();
          }
          final showLegacyRoomSurface = beaconViewShowsLegacyRoomSurface(
            isSplit: isSplit,
            roomRequestedByRoute: _roomFromRouteParams(widget),
            canNavigateBeaconRoom: state.canNavigateBeaconRoom,
          );
          final roomUnread = _effectiveRoomUnreadCount(
            state,
            useLiveRoomCubit: showLegacyRoomSurface || isSplit,
          );
          final statusSlots = beaconViewStatusSlots(l10n, state);
          final (appBarStatusLine, appBarStatusTone) = showLegacyRoomSurface
              ? beaconViewRoomAppBarStatus(l10n, roomUnread)
              : (
                  statusSlots.displayLine,
                  statusSlots.tone,
                );

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
              onRetry: () => unawaited(beaconViewCubit.retryInitialLoad()),
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
              onRetry: () => unawaited(beaconViewCubit.retryInitialLoad()),
              onGoBack: () => _leaveBeaconView(context),
            );
          } else if (isSplit) {
            body = _buildExpandedSplitBody(
              state: state,
              beaconViewCubit: beaconViewCubit,
              screenCubit: screenCubit,
              tt: tt,
            );
          } else if (showLegacyRoomSurface) {
            body = _buildRoomPane(state);
          } else {
            body = _buildOperationalBody(
              beaconViewCubit: beaconViewCubit,
              screenCubit: screenCubit,
            );
          }

          return PopScope(
            canPop: isSplit || !showLegacyRoomSurface,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              // Browser/system back: URL sync only — do not maybePop (see
              // [_exitRoomSurface]).
              _exitRoomSurface();
            },
            child: Scaffold(
              appBar: TenturaTopBar.of(
                context,
                alignment: isSplit
                    ? TenturaTopBarAlignment.fullWidth
                    : TenturaTopBarAlignment.content,
                // Plain BackButton (no onPressed): let it fall through to
                // Navigator.maybePop so a tap routes through the same
                // PopScope.onPopInvokedWithResult → _exitRoomSurface() path
                // that browser/system back already uses. Wiring onPressed
                // directly to _exitRoomSurface bypassed the Navigator pop
                // attempt entirely and hung on compact — the replacePath in
                // _stripRoomFromUrl never resolved when called that way.
                leading: isSplit
                    ? null
                    : showLegacyRoomSurface
                    ? const BackButton()
                    : AutoLeadingWithFallback(
                        fallbackPath: kPathMyWork,
                        onFallback: () => _leaveBeaconView(context),
                      ),
                title: isSplit
                    ? const SizedBox.shrink()
                    : BeaconViewAppBarTitle(
                        beacon: state.beacon,
                        showBeaconContent: showBeaconContent,
                        statusLine: appBarStatusLine,
                        statusTone: appBarStatusTone,
                        l10n: l10n,
                      ),
                actions: isSplit
                    ? null
                    : [
                        if (showBeaconContent &&
                            !showInitialLoading &&
                            !showLegacyRoomSurface &&
                            state.canNavigateBeaconRoom)
                          BeaconViewRoomAppBarButton(
                            state: state,
                            onPressed: _enterRoomSurface,
                          ),
                        if (showBeaconContent)
                          beaconViewAppBarOverflow(
                            context: context,
                            state: state,
                            cubit: beaconViewCubit,
                            screenCubit: screenCubit,
                            l10n: l10n,
                            inRoomSurface: showLegacyRoomSurface,
                            roomCubit: showLegacyRoomSurface
                                ? _roomCubit
                                : null,
                            onItemsTabRefresh: _refreshItemsTab,
                            onAuthorManageStatus: () async {
                              await showBeaconViewUpdateStatusSheet(
                                context,
                                state,
                                beaconViewCubit,
                                onOpenPeopleTab: () =>
                                    _switchToTab(kBeaconTabPeople),
                                onEnterRoomSurface: _enterRoomSurface,
                              );
                            },
                          ),
                      ],
                row: isSplit
                    ? LayoutBuilder(
                        builder: (context, constraints) {
                          final roomPaneWidth = beaconViewRoomSplitPaneWidth(
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
                                  onItemsTabRefresh: _refreshItemsTab,
                                  onAuthorManageStatus: () async {
                                    await showBeaconViewUpdateStatusSheet(
                                      context,
                                      state,
                                      beaconViewCubit,
                                      onOpenPeopleTab: () =>
                                          _switchToTab(kBeaconTabPeople),
                                      onEnterRoomSurface: _enterRoomSurface,
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
                                            _leaveBeaconView(context),
                                      ),
                                      Expanded(
                                        child: BeaconViewAppBarTitle(
                                          beacon: state.beacon,
                                          showBeaconContent: showBeaconContent,
                                          statusLine: appBarStatusLine,
                                          statusTone: appBarStatusTone,
                                          l10n: l10n,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              SizedBox(
                                width: roomPaneWidth,
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: overflow,
                                ),
                              ),
                            ],
                          );
                        },
                      )
                    : null,
                progress: TenturaTopBar.loadingBar(context, state.isLoading),
              ),
              body: SafeArea(
                child: Column(
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
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
