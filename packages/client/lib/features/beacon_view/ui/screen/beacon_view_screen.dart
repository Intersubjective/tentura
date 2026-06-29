import 'dart:async';

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
import 'package:tentura/ui/widget/linear_pi_active.dart';

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
  late bool _showRoomSurface;

  /// Coordination item / participant to scroll-to + flash after a Log row tap.
  String? _focusItemId;
  String? _focusUserId;

  RoomCubit? _roomCubit;
  ItemsTabCubit? _itemsTabCubit;
  bool _didApplyFetchResolution = false;
  String? _bannerMessage;

  /// True after the user leaves the room surface until they open it again.
  /// Prevents [didUpdateWidget] from re-opening room while `?tab=room` is still
  /// on the URL briefly after [replacePath] / history sync.
  bool _userDismissedRoomSurface = false;

  bool _roomExitInProgress = false;

  /// Set when [_enterRoomSurface] used [StackRouter.pushPath] for `?tab=room`.
  /// Exit must [StackRouter.back] to drop that history entry — [replacePath]
  /// would leave a duplicate beacon URL and force two pops to leave the beacon.
  bool _roomEnteredViaPush = false;

  /// Ensures mark-seen on the previous visit finishes before re-open refresh.
  Future<void>? _pendingRoomExit;

  void _unfocusForRouteChange() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _leaveBeaconView(BuildContext context) {
    final router = context.router;
    if (router.canPop()) {
      router.back();
      return;
    }
    unawaited(router.replacePath(kPathMyWork));
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

  bool _roomFromRouteParams(BeaconViewScreen w) {
    final legacySurface = w.surface?.trim().toLowerCase();
    return legacySurface == kBeaconSurfaceRoomQueryValue ||
        w.viewTab == 'room' ||
        normalizeBeaconViewEntry(
              isDeepLink: w.isDeepLink,
              rawFromQuery: BeaconViewEntrySourceWire.parseQuery(w.entry),
            ) ==
            BeaconViewEntrySource.roomNotification;
  }

  String _beaconViewPath({String? viewTab}) {
    final q = <String, String>{};
    if (viewTab != null && viewTab.isNotEmpty) {
      q[kQueryBeaconViewTab] = viewTab;
    }
    final entry = widget.entry?.trim();
    if (entry != null && entry.isNotEmpty) {
      q[kQueryBeaconEntry] = entry;
    }
    final base = '$kPathBeaconView/${widget.id}';
    if (q.isEmpty) return base;
    return '$base?${Uri(queryParameters: q).query}';
  }

  @override
  void initState() {
    super.initState();
    _showRoomSurface = _roomFromRouteParams(widget);
    _tabIndex = _beaconViewTabIndex(widget.viewTab).clamp(
      0,
      kBeaconTabCount - 1,
    );
    _peopleTabAttentionActive =
        _beaconPeopleTabAttentionQueryTruthy(widget.peopleTabAttention) &&
        _tabIndex == kBeaconTabPeople;
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
      _userDismissedRoomSurface = false;
      _roomExitInProgress = false;
      _roomEnteredViaPush = false;
    }
    final wasRoom = _roomFromRouteParams(oldWidget);
    final isRoom = _roomFromRouteParams(widget);
    if (wasRoom && !isRoom && _showRoomSurface) {
      _roomEnteredViaPush = false;
      _exitRoomSurface(fromRouteSync: true);
    } else if (!wasRoom &&
        isRoom &&
        !_showRoomSurface &&
        !_userDismissedRoomSurface) {
      // URL moved to ?tab=room while room is closed — treat this as an entry
      // signal and clear any stale exit-in-progress flag for the same reason
      // as in _enterRoomSurface above.
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

  void _applyFetchResolution(BeaconViewState s) {
    if (!s.isSuccess || _didApplyFetchResolution) return;

    final roomDenied = _showRoomSurface && !s.canNavigateBeaconRoom;
    if (roomDenied && (!s.beaconContextLoaded || s.myProfile.id.isEmpty)) {
      return;
    }

    setState(() {
      if (roomDenied) {
        _showRoomSurface = false;
        if (s.showsRoomAccessUnavailableBanner) {
          _bannerMessage = L10n.of(
            context,
          )!.beaconViewRoomAccessUnavailableBanner;
        } else {
          unawaited(_stripRoomFromUrl());
        }
      }
      _didApplyFetchResolution = true;
      if (_showRoomSurface && s.canNavigateBeaconRoom) {
        _ensureEmbeddedRoomCubit();
        final itemId = widget.coordinationItemId?.trim();
        if (itemId != null && itemId.isNotEmpty) {
          _roomCubit!.prepareThreadScroll(coordinationItemId: itemId);
        }
      }
    });
  }

  void _applyRoomSurfaceState({
    required bool open,
    bool fromRouteSync = false,
  }) {
    if (open) {
      setState(() {
        _userDismissedRoomSurface = false;
        _showRoomSurface = true;
        _ensureEmbeddedRoomCubit();
      });
      unawaited(_onRoomSurfaceOpened());
    } else {
      if (!_showRoomSurface) return;
      if (!fromRouteSync) {
        _userDismissedRoomSurface = true;
      }
      setState(() => _showRoomSurface = false);
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
  int _effectiveRoomUnreadCount(BeaconViewState beaconState) {
    final rc = _roomCubit;
    if (_showRoomSurface && rc != null && !rc.isClosed) {
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

  Future<void> _stripRoomFromUrl() {
    return context.router.replacePath(_beaconViewPath());
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
    // Push a dedicated `?tab=room` route instead of also embedding room on the
    // route below — otherwise back pops the top route but leaves a live
    // [RoomCubit] + `_showRoomSurface` on the underlying beacon view.
    if (!_roomFromRouteParams(widget)) {
      _userDismissedRoomSurface = false;
      _roomEnteredViaPush = true;
      final roomPath = _beaconViewPath(viewTab: 'room');
      // Push so browser history retains the operational beacon URL; exit via
      // [StackRouter.back] (not replacePath) to avoid duplicate beacon entries.
      _unfocusForRouteChange();
      unawaited(context.router.pushPath(roomPath));
      return;
    }
    _roomEnteredViaPush = false;
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

    if (fromRouteSync) {
      _roomEnteredViaPush = false;
      if (_showRoomSurface) {
        _applyRoomSurfaceState(open: false, fromRouteSync: true);
      }
      return;
    }

    _roomExitInProgress = true;
    if (_showRoomSurface) {
      _applyRoomSurfaceState(open: false);
    }

    // Room opened via pushPath: pop the `?tab=room` history entry. Using
    // replacePath here duplicates `/beacon/view/:id` in the stack/history.
    if (_roomEnteredViaPush) {
      _roomEnteredViaPush = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          _roomExitInProgress = false;
          return;
        }
        _unfocusForRouteChange();
        context.router.back();
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
      unawaited(
        _stripRoomFromUrl().whenComplete(() {
          if (mounted) {
            _roomExitInProgress = false;
          }
        }),
      );
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

  @override
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final beaconViewCubit = context.read<BeaconViewCubit>();
    final l10n = L10n.of(context)!;
    return BlocListener<BeaconViewCubit, BeaconViewState>(
      listenWhen: (p, c) =>
          (!p.isSuccess && c.isSuccess) ||
          (_showRoomSurface &&
              !p.canNavigateBeaconRoom &&
              c.canNavigateBeaconRoom) ||
          (_showRoomSurface &&
              p.canNavigateBeaconRoom &&
              !c.canNavigateBeaconRoom),
      listener: (ctx, s) {
        if (!s.isSuccess) return;
        if (!ctx.mounted) return;
        if (_showRoomSurface && !s.canNavigateBeaconRoom) {
          if (!s.beaconContextLoaded) return;
          if (s.myProfile.id.isEmpty) return;
          unawaited(_releaseEmbeddedRoomCubit());
          setState(() {
            _showRoomSurface = false;
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

          final roomUnread = _effectiveRoomUnreadCount(state);
          final statusSlots = beaconViewStatusSlots(l10n, state);
          final (appBarStatusLine, appBarStatusTone) = _showRoomSurface
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
          } else if (_showRoomSurface && state.canNavigateBeaconRoom) {
            final roomCubit = _roomCubit;
            body = roomCubit == null || roomCubit.isClosed
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
          } else {
            if (_itemsTabCubit == null) {
              _itemsTabCubit = ItemsTabCubit(beaconId: widget.id);
              unawaited(_itemsTabCubit!.fetch());
            }
            body = TenturaContentColumn(
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

          return PopScope(
            canPop: !_showRoomSurface,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) return;
              // Browser/system back: URL sync only — do not maybePop (see
              // [_exitRoomSurface]).
              _exitRoomSurface();
            },
            child: Scaffold(
              appBar: AppBar(
                backgroundColor: scheme.surface,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                toolbarHeight: kToolbarHeight,
                leadingWidth: kToolbarHeight,
                foregroundColor: scheme.onSurface,
                titleTextStyle: theme.textTheme.titleLarge!.copyWith(
                  color: scheme.onSurface,
                ),
                titleSpacing: 8,
                leading: _showRoomSurface
                    ? BackButton(onPressed: _exitRoomSurface)
                    : AutoLeadingWithFallback(
                        fallbackPath: kPathMyWork,
                        onFallback: () => _leaveBeaconView(context),
                      ),
                title: BeaconViewAppBarTitle(
                  beacon: state.beacon,
                  showBeaconContent: showBeaconContent,
                  statusLine: appBarStatusLine,
                  statusTone: appBarStatusTone,
                  l10n: l10n,
                ),
                actions: [
                  if (showBeaconContent &&
                      !showInitialLoading &&
                      !_showRoomSurface &&
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
                      inRoomSurface: _showRoomSurface,
                      roomCubit: _showRoomSurface ? _roomCubit : null,
                      onItemsTabRefresh: _refreshItemsTab,
                      onAuthorManageStatus: () async {
                        await showBeaconViewUpdateStatusSheet(
                          context,
                          state,
                          beaconViewCubit,
                          onOpenPeopleTab: () => _switchToTab(kBeaconTabPeople),
                          onEnterRoomSurface: _enterRoomSurface,
                        );
                      },
                    ),
                ],
                bottom: PreferredSize(
                  preferredSize: LinearPiActive.size,
                  child: LinearPiActive.builder(context, state.isLoading),
                ),
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
