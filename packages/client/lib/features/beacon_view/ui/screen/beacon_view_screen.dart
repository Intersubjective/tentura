import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/coordination_room_navigation.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_state.dart';
import 'package:tentura/features/beacon_view/domain/beacon_view_entry_source.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lifecycle_ui.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/util/beacon_lineage_overflow_actions.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_promise_sheet.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_prepared_promise_sheet.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';

import '../bloc/beacon_view_cubit.dart';
import '../dialog/help_offer_message_dialog.dart';
import '../widget/activity_list.dart';
import '../widget/beacon_current_line_sheet.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_lineage_parent_link.dart';
import '../widget/beacon_operational_header_card.dart';
import '../util/beacon_hud_derivation.dart';
import '../widget/beacon_anchor_status.dart';
import '../widget/beacon_view_app_bar_title.dart';
import '../widget/beacon_prepared_ask_sheet.dart';
import '../widget/beacon_prepared_blocker_sheet.dart';
import '../widget/beacon_people_tab_body.dart';
import '../widget/items_tab.dart';

bool _beaconPeopleTabAttentionQueryTruthy(String? v) {
  if (v == null || v.isEmpty) return false;
  final s = v.toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

/// Operational tab indices: items(0), people(1), log(2). Room is a separate surface.
const int kBeaconTabItems = 0;
const int kBeaconTabPeople = 1;
const int kBeaconTabLog = 2;
const int _kBeaconTabCount = 3;

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

bool _forwardInPrimaryCta(BeaconViewState state) {
  final b = state.beacon;
  if (state.isBeaconMine || b.lifecycle != BeaconLifecycle.open) {
    return false;
  }
  if (!state.isHelpOffered && b.allowsNewHelpOfferAsNonAuthor) {
    return true;
  }
  if (state.isHelpOffered && !b.allowsWithdrawWhileHelpOffered) {
    return true;
  }
  return false;
}

bool _hideOfferHelpWithdrawFromOverflow(BeaconViewState state) {
  final b = state.beacon;
  if (state.isBeaconMine || b.lifecycle != BeaconLifecycle.open) {
    return false;
  }
  if (!state.isHelpOffered && b.allowsNewHelpOfferAsNonAuthor) {
    return true;
  }
  if (state.isHelpOffered && b.allowsWithdrawWhileHelpOffered) {
    return true;
  }
  return false;
}

const _beaconAuthorUpdateEditWindow = Duration(hours: 1);

/// Initial help offer dialog + [BeaconViewCubit.offerHelp].
Future<void> _beaconViewRunInitialHelpOfferDialog(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  if (!context.mounted) return;
  final useOfferHelpAnyway =
      cubit.state.beacon.coordinationStatus ==
      BeaconCoordinationStatus.enoughHelpOffered;
  final outcome = await HelpOfferMessageDialog.show(
    context,
    title: useOfferHelpAnyway
        ? l10n.dialogOfferHelpAnywayTitle
        : l10n.dialogOfferHelpTitle,
    hintText: l10n.hintOfferHelpMessage,
    allowEmptyMessage: true,
    showHelpTypeChips: true,
  );
  if (outcome != null && context.mounted) {
    await cubit.offerHelp(
      message: outcome.message,
      helpTypes: outcome.helpTypesWire,
    );
  }
}

Future<void> _beaconViewOpenForwardThenMaybeNudgeOfferHelp(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  final id = cubit.state.beacon.id;
  final didForward = await context.router.push<bool>(
    ForwardBeaconRoute(beaconId: id),
  );
  if (!context.mounted || didForward != true) return;
  final s = cubit.state;
  if (s.isHelpOffered ||
      s.isBeaconMine ||
      !s.beacon.allowsNewHelpOfferAsNonAuthor ||
      s.beacon.lifecycle != BeaconLifecycle.open) {
    return;
  }
  showSnackBar(
    context,
    text: l10n.nudgeOfferHelpAfterForward,
    action: SnackBarAction(
      label: l10n.labelOfferHelp,
      onPressed: () => unawaited(
        _beaconViewRunInitialHelpOfferDialog(context, cubit, l10n),
      ),
    ),
  );
}

bool _authorUpdateEditableNow(DateTime createdAt) =>
    DateTime.now().toUtc().difference(createdAt.toUtc()) <=
    _beaconAuthorUpdateEditWindow;

bool _authorLifecycleToggleEnabled(BeaconViewState state) {
  final b = state.beacon;
  if (b.lifecycle == BeaconLifecycle.open && b.isListed) {
    return state.closureActionPriority != ClosureActionPriority.hidden;
  }
  return true;
}

String _beaconViewRoomAppBarTooltip(BeaconViewState state, L10n l10n) {
  if (state.canNavigateBeaconRoom) {
    return l10n.beaconRoomOpen;
  }
  if (state.isRoomAdmissionBlocked) {
    return state.coordinationDeniesRoomAdmission
        ? l10n.beaconRoomNoAdmission
        : l10n.beaconRoomWaitingForApproval;
  }
  return l10n.beaconViewRoomAccessUnavailableBanner;
}

Future<void> _beaconViewRunAuthorCloseSheet({
  required BuildContext context,
  required BeaconViewCubit cubit,
  required L10n l10n,
  required void Function() onOpenPeopleTab,
  required void Function([CoordinationItem? focusItem]) onEnterRoomSurface,
}) async {
  if (!context.mounted) return;
  var summary = buildClosureConfirmationSummary(cubit.state);

  Future<bool> attemptClose(bool expected) async {
    final result = await cubit.closeBeacon(
      expectedRequiresReviewWindow: expected,
    );
    if (!context.mounted || result == null) return false;
    if (result.branchMismatch) {
      if (!context.mounted) return false;
      summary = buildClosureConfirmationSummary(cubit.state);
      return showBeaconCloseConfirmSheet(
        context: context,
        summary: summary,
        isLoading: cubit.state.isLoading,
        onCloseBeacon: attemptClose,
        onOpenPeople: onOpenPeopleTab,
        onPostUpdate: () async {
          await _showPostAuthorUpdateSheet(context, cubit, l10n);
        },
        onResolveRoom: cubit.state.canNavigateBeaconRoom
            ? () => onEnterRoomSurface()
            : null,
      );
    }
    return true;
  }

  await showBeaconCloseConfirmSheet(
    context: context,
    summary: summary,
    isLoading: cubit.state.isLoading,
    onCloseBeacon: attemptClose,
    onOpenPeople: onOpenPeopleTab,
    onPostUpdate: () async {
      await _showPostAuthorUpdateSheet(context, cubit, l10n);
    },
    onResolveRoom: cubit.state.canNavigateBeaconRoom
        ? () => onEnterRoomSurface()
        : null,
  );
}

bool _canShowCreatePromise(BeaconViewState state) {
  final b = state.beacon;
  if (b.lifecycle != BeaconLifecycle.open) return false;
  if (!state.isAuthorOrSteward && !state.hasRoomAdmission) return false;
  return hasPublishedPromiseTargets(
    participants: state.roomParticipants,
    myUserId: state.myProfile.id,
    isAuthorOrSteward: state.isAuthorOrSteward,
  );
}

Widget _beaconViewAppBarOverflow({
  required BuildContext context,
  required BeaconViewState state,
  required BeaconViewCubit cubit,
  required ScreenCubit screenCubit,
  required L10n l10n,
  required Future<void> Function() onAuthorListedOpenClose,
  required VoidCallback onItemsTabRefresh,
}) {
  final b = state.beacon;
  final beaconId = b.id;
  final hideOverflowForward = _forwardInPrimaryCta(state);
  final hideOfferHelpWithdraw = _hideOfferHelpWithdrawFromOverflow(state);

  if (state.isBeaconMine) {
    return BeaconOverflowMenu(
      beacon: b,
      onShare: () => unawaited(
        ShareCodeDialog.show(
          context,
          link: Uri.parse(kServerName).replace(
            queryParameters: {'id': beaconId},
            path: kPathAppLinkView,
          ),
          header: beaconId,
        ),
      ),
      onCloseBeacon: state.isBeaconMine &&
              state.beacon.lifecycle == BeaconLifecycle.open &&
              state.closureActionPriority != ClosureActionPriority.hidden
          ? () async {
              if (!context.mounted) return;
              await onAuthorListedOpenClose();
            }
          : null,
      onCancelBeacon: state.isBeaconMine && beaconAllowsCancel(b)
          ? () async {
              if (!context.mounted) return;
              await cubit.cancelBeacon();
            }
          : null,
      onEdit: b.lifecycle == BeaconLifecycle.open
          ? () => unawaited(
              context.router.pushPath(
                '$kPathBeaconNew?$kQueryBeaconEditId=$beaconId',
              ),
            )
          : null,
      onCreateFrom: beaconAllowsLineageOverflow(b)
          ? () async {
              await runBeaconCreateFromAction(
                context,
                fork: () => cubit.forkFromThis(),
              );
            }
          : null,
      onPrepareAsk: b.lifecycle == BeaconLifecycle.open
          ? () => unawaited(
              showPreparedAskEditorSheet(
                context,
                beaconId: beaconId,
                onSaved: onItemsTabRefresh,
              ),
            )
          : null,
      onPrepareBlocker: b.lifecycle == BeaconLifecycle.open
          ? () => unawaited(
              showPreparedBlockerEditorSheet(
                context,
                beaconId: beaconId,
                onSaved: onItemsTabRefresh,
              ),
            )
          : null,
      onPreparePromise: b.lifecycle == BeaconLifecycle.open
          ? () => unawaited(
              showPreparedPromiseEditorSheet(
                context,
                beaconId: beaconId,
                onSaved: onItemsTabRefresh,
              ),
            )
          : null,
      onCreatePromise: _canShowCreatePromise(state)
          ? () => unawaited(
              showBeaconRoomPromiseSheet(
                context,
                beaconId: beaconId,
                participants: state.roomParticipants,
                myUserId: state.myProfile.id,
                isAuthorOrSteward: state.isAuthorOrSteward,
                onSaved: onItemsTabRefresh,
              ),
            )
          : null,
      onForward: () => unawaited(
        _beaconViewOpenForwardThenMaybeNudgeOfferHelp(context, cubit, l10n),
      ),
      onForwardsGraph: () => screenCubit.showForwardsGraphFor(beaconId),
      onLineageSuggestions: beaconAllowsLineageOverflow(b)
          ? () => runBeaconLineageSuggestionsPreview(
              context,
              beaconId: beaconId,
            )
          : null,
      onDraftReview: state.showDraftEvaluationCta
          ? () => unawaited(
              context.router.pushPath(
                '$kPathReviewContributions/$beaconId?draft=true',
              ),
            )
          : null,
      onDelete: () async {
        if (!context.mounted) return;
        if (await BeaconDeleteDialog.show(
              context,
              lifecycle: b.lifecycle,
              hasEverHadCommitter: beaconDeleteBlockedByCommitters(b),
            ) ??
            false) {
          if (!context.mounted) return;
          await cubit.delete(beaconId);
        }
      },
    );
  }

  return BeaconOverflowMenu(
    beacon: b,
    onCreatePromise: _canShowCreatePromise(state)
        ? () => unawaited(
            showBeaconRoomPromiseSheet(
              context,
              beaconId: beaconId,
              participants: state.roomParticipants,
              myUserId: state.myProfile.id,
              isAuthorOrSteward: state.isAuthorOrSteward,
              onSaved: onItemsTabRefresh,
            ),
          )
        : null,
    onOfferHelp:
        !hideOfferHelpWithdraw &&
            !state.isHelpOffered &&
            b.allowsNewHelpOfferAsNonAuthor
        ? () async {
            await _beaconViewRunInitialHelpOfferDialog(context, cubit, l10n);
          }
        : null,
    onWithdraw:
        !hideOfferHelpWithdraw &&
            state.isHelpOffered &&
            b.allowsWithdrawWhileHelpOffered
        ? () async {
            if (!context.mounted) return;
            final outcome = await HelpOfferMessageDialog.show(
              context,
              title: l10n.dialogWithdrawHelpOfferTitle,
              hintText: l10n.hintWithdrawReason,
              allowEmptyMessage: true,
              requireWithdrawReason: true,
            );
            if (outcome?.withdrawReasonWire != null && context.mounted) {
              await cubit.withdraw(
                message: outcome!.message,
                withdrawReason: outcome.withdrawReasonWire!,
              );
            }
          }
        : null,
    onForward: hideOverflowForward
        ? null
        : () => unawaited(
            _beaconViewOpenForwardThenMaybeNudgeOfferHelp(context, cubit, l10n),
          ),
    onForwardsGraph: () => screenCubit.showForwardsGraphFor(beaconId),
    onCreateFrom: beaconAllowsLineageOverflow(b)
        ? () async {
            await runBeaconCreateFromAction(
              context,
              fork: () => cubit.forkFromThis(),
            );
          }
        : null,
    onLineageSuggestions: beaconAllowsLineageOverflow(b)
        ? () => runBeaconLineageSuggestionsPreview(
            context,
            beaconId: beaconId,
          )
        : null,
    onDraftReview: state.showDraftEvaluationCta
        ? () => unawaited(
            context.router.pushPath(
              '$kPathReviewContributions/$beaconId?draft=true',
            ),
          )
        : null,
    onWatch: !state.isHelpOffered && state.inboxStatus == InboxItemStatus.needsMe
        ? () => unawaited(cubit.moveToWatching())
        : null,
    onStopWatching:
        !state.isHelpOffered && state.inboxStatus == InboxItemStatus.watching
        ? () => unawaited(cubit.stopWatching())
        : null,
    onCantHelp:
        state.inboxStatus == InboxItemStatus.needsMe ||
            state.inboxStatus == InboxItemStatus.watching
        ? () async {
            if (!context.mounted) return;
            final msg = await showRejectionDialog(context);
            if (context.mounted && msg != null) {
              await cubit.rejectInbox(message: msg);
            }
          }
        : null,
    onMoveToInbox: state.inboxStatus == InboxItemStatus.rejected
        ? () => unawaited(cubit.unrejectInbox())
        : null,
    onComplaint: () => screenCubit.showComplaint(beaconId),
  );
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
  Widget wrappedRoute(_) => MultiBlocProvider(
    providers: [
      BlocProvider(
        create: (_) => ScreenCubit(),
      ),
      BlocProvider(
        create: (_) => BeaconViewCubit(
          myProfile: GetIt.I<ProfileCubit>().state.profile,
          id: id,
        ),
      ),
    ],
    child: MultiBlocListener(
      listeners: const [
        BlocListener<ScreenCubit, ScreenState>(
          listener: commonScreenBlocListener,
        ),
        BlocListener<BeaconViewCubit, BeaconViewState>(
          listener: commonScreenBlocListener,
        ),
      ],
      child: this,
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
      _kBeaconTabCount - 1,
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

    setState(() {
      if (roomDenied) {
        _showRoomSurface = false;
        _bannerMessage = L10n.of(context)!.beaconViewRoomAccessUnavailableBanner;
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
    final initialAnchor =
        context.read<BeaconViewCubit>().roomReadThrough(widget.id);
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
    final needsUrlSync =
        _urlIndicatesRoom() || _roomFromRouteParams(widget);
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
    if (tab < 0 || tab >= _kBeaconTabCount) return;
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
              p.canNavigateBeaconRoom &&
              !c.canNavigateBeaconRoom),
      listener: (ctx, s) {
        if (!s.isSuccess) return;
        if (!ctx.mounted) return;
        if (_showRoomSurface && !s.canNavigateBeaconRoom) {
          unawaited(_releaseEmbeddedRoomCubit());
          setState(() {
            _showRoomSurface = false;
            _bannerMessage = L10n.of(
              ctx,
            )!.beaconViewRoomAccessUnavailableBanner;
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
          final showInitialLoading =
              state.isLoading &&
              state.timeline.isEmpty &&
              state.helpOffers.isEmpty;


          final roomUnread = _effectiveRoomUnreadCount(state);
          final statusSlots = beaconViewStatusSlots(l10n, state);
          final (appBarStatusLine, appBarStatusTone) = _showRoomSurface
              ? (roomUnread > 0
                    ? (
                        'ROOM · Unread: $roomUnread',
                        TenturaTone.info,
                      )
                    : ('ROOM · UP-TO-DATE', TenturaTone.neutral))
              : (
                  statusSlots.displayLine,
                  statusSlots.tone,
                );

          Widget body;
          if (showInitialLoading) {
            body = const Center(
              child: CircularProgressIndicator.adaptive(),
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
                      child: const BeaconRoomSurface(),
                    ),
                  );
          } else {
            if (_itemsTabCubit == null) {
              _itemsTabCubit = ItemsTabCubit(beaconId: widget.id);
              unawaited(_itemsTabCubit!.fetch());
            }
            body = BlocProvider.value(
              value: _itemsTabCubit!,
              child: _BeaconOperationalScrollView(
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
                onAuthorCloseRequested: (ctx) => _beaconViewRunAuthorCloseSheet(
                  context: ctx,
                  cubit: beaconViewCubit,
                  l10n: L10n.of(ctx)!,
                  onOpenPeopleTab: () =>
                      _switchToTab(kBeaconTabPeople),
                  onEnterRoomSurface: _enterRoomSurface,
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
                    : const AutoLeadingWithFallback(
                        fallbackPath: kPathHome,
                      ),
                title: BeaconViewAppBarTitle(
                  beacon: state.beacon,
                  statusLine: appBarStatusLine,
                  statusTone: appBarStatusTone,
                  l10n: l10n,
                ),
                actions: [
                  if (!showInitialLoading &&
                      !_showRoomSurface &&
                      state.canNavigateBeaconRoom)
                    Badge(
                      isLabelVisible: state.roomUnreadCount > 0,
                      label: Text('${state.roomUnreadCount}'),
                      child: IconButton(
                        tooltip: _beaconViewRoomAppBarTooltip(state, l10n),
                        icon: const Icon(Icons.forum_rounded),
                        onPressed: _enterRoomSurface,
                      ),
                    ),
                  _beaconViewAppBarOverflow(
                    context: context,
                    state: state,
                    cubit: beaconViewCubit,
                    screenCubit: screenCubit,
                    l10n: l10n,
                    onItemsTabRefresh: _refreshItemsTab,
                    onAuthorListedOpenClose: () =>
                        _beaconViewRunAuthorCloseSheet(
                          context: context,
                          cubit: beaconViewCubit,
                          l10n: l10n,
                          onOpenPeopleTab: () =>
                              _switchToTab(kBeaconTabPeople),
                          onEnterRoomSurface: _enterRoomSurface,
                        ),
                  ),
                ],
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(4),
                  child: LinearPiActive.builder(context, state.isLoading),
                ),
              ),
              body: Column(
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
          );
        },
      ),
    );
  }
}

class _BeaconOperationalScrollView extends StatelessWidget {
  const _BeaconOperationalScrollView({
    required this.beaconViewCubit,
    required this.screenCubit,
    required this.tabIndex,
    required this.onTabChanged,
    required this.peopleTabAttentionActive,
    required this.onPeopleTabAttentionCleared,
    required this.focusItemId,
    required this.focusUserId,
    required this.onOperationalFocusCleared,
    required this.onTapCoordinationLogEvent,
    required this.onEnterRoomSurface,
    required this.onOpenItemDiscussion,
    required this.onAuthorCloseRequested,
  });

  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  /// Pulse/highlight People tab until first pointer interaction or tab change.
  final bool peopleTabAttentionActive;
  final VoidCallback onPeopleTabAttentionCleared;

  /// Coordination item / participant to focus + flash (Log row tap-to-focus).
  final String? focusItemId;
  final String? focusUserId;
  final VoidCallback onOperationalFocusCleared;
  final void Function(BeaconActivityEvent event) onTapCoordinationLogEvent;

  final void Function([CoordinationItem? focusItem]) onEnterRoomSurface;

  final void Function(CoordinationItem item) onOpenItemDiscussion;

  final Future<void> Function(BuildContext context) onAuthorCloseRequested;

  void _setTab(int i) {
    if (tabIndex == i) {
      onPeopleTabAttentionCleared();
      return;
    }
    onTabChanged(i);
  }

  void _onPointerDown(PointerDownEvent _) {
    if (peopleTabAttentionActive) {
      onPeopleTabAttentionCleared();
    }
    if (focusItemId != null || focusUserId != null) {
      onOperationalFocusCleared();
    }
  }

  Future<void> _showUpdateStatusSheet(
    BuildContext context,
    BeaconViewState state,
  ) async {
    final l10n = L10n.of(context)!;
    final publicOptions = <(int, String)>[
      (0, l10n.beaconPublicStatusOpen),
      (1, l10n.beaconPublicStatusCoordinating),
      (2, l10n.beaconPublicStatusMoreHelp),
      (3, l10n.beaconPublicStatusEnoughHelp),
      (4, l10n.beaconPublicStatusClosed),
    ];
    final coordinationOptions = <(int, String)>[
      (
        BeaconCoordinationStatus.neutral.smallintValue,
        l10n.coordinationNeutral,
      ),
      (
        BeaconCoordinationStatus.moreOrDifferentHelpNeeded.smallintValue,
        l10n.coordinationMoreHelpNeeded,
      ),
      (
        BeaconCoordinationStatus.enoughHelpOffered.smallintValue,
        l10n.coordinationEnoughHelp,
      ),
    ];
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final tt = ctx.tt;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(tt.screenHPadding, 4, tt.screenHPadding, 4),
                child: Text(
                  l10n.beaconPublicStatusCardTitle,
                  style: Theme.of(ctx).textTheme.titleSmall,
                ),
              ),
              for (final o in publicOptions)
                ListTile(
                  dense: true,
                  leading: state.beacon.publicStatus == o.$1
                      ? const Icon(Icons.check)
                      : const SizedBox(width: 24),
                  title: Text(o.$2),
                  onTap: () {
                    Navigator.of(ctx).pop();
                    unawaited(beaconViewCubit.updatePublicStatus(o.$1));
                  },
                ),
              if (state.isBeaconMine) ...[
                const Divider(height: 8),
                Padding(
                  padding: EdgeInsets.fromLTRB(tt.screenHPadding, 4, tt.screenHPadding, 4),
                  child: Text(
                    l10n.coordinationSetOverallStatus,
                    style: Theme.of(ctx).textTheme.titleSmall,
                  ),
                ),
                for (final o in coordinationOptions)
                  ListTile(
                    dense: true,
                    title: Text(o.$2),
                    onTap: () {
                      Navigator.of(ctx).pop();
                      unawaited(
                        beaconViewCubit.setBeaconCoordinationStatus(
                          BeaconCoordinationStatus.fromSmallint(o.$1),
                        ),
                      );
                    },
                  ),
              ],
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  Future<void> _beaconViewAuthorCloseFlow(BuildContext context) async {
    await onAuthorCloseRequested(context);
  }

  Future<void> _runOfferHelpFlow(BuildContext context, L10n l10n) async {
    await _beaconViewRunInitialHelpOfferDialog(
      context,
      beaconViewCubit,
      l10n,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final idx = tabIndex.clamp(0, _kBeaconTabCount - 1);
    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      bloc: beaconViewCubit,
      buildWhen: (p, c) =>
          p.beacon != c.beacon ||
          p.beacon.coordinationStatus != c.beacon.coordinationStatus ||
          p.beacon.lifecycle != c.beacon.lifecycle ||
          p.timeline != c.timeline ||
          p.roomActivityEvents != c.roomActivityEvents ||
          p.helpOffers != c.helpOffers ||
          p.isHelpOffered != c.isHelpOffered ||
          p.isLoading != c.isLoading ||
          p.forwardProvenance != c.forwardProvenance ||
          p.inboxStatus != c.inboxStatus ||
          p.viewerForwardEdges != c.viewerForwardEdges ||
          p.forwardsLoaded != c.forwardsLoaded ||
          p.forwardsLoading != c.forwardsLoading ||
          p.factCards != c.factCards ||
          p.roomParticipants.length != c.roomParticipants.length ||
          (p.roomParticipants
                  .map(
                    (e) =>
                        '${e.userId}|${e.userTitle}|${e.nextMoveText}|${e.status}|${e.nextMoveStatus}',
                  )
                  .join() !=
              c.roomParticipants
                  .map(
                    (e) =>
                        '${e.userId}|${e.userTitle}|${e.nextMoveText}|${e.status}|${e.nextMoveStatus}',
                  )
                  .join()) ||
          p.beaconRoomCue?.lastRoomMeaningfulChange !=
              c.beaconRoomCue?.lastRoomMeaningfulChange ||
          p.beaconRoomCue?.currentLine != c.beaconRoomCue?.currentLine ||
          p.beaconRoomCue?.openBlockerTitle !=
              c.beaconRoomCue?.openBlockerTitle ||
          p.showDraftEvaluationCta != c.showDraftEvaluationCta ||
          p.unansweredHelpOffersCount != c.unansweredHelpOffersCount ||
          p.needCoordinationHelpOffersCount !=
              c.needCoordinationHelpOffersCount,
      builder: (context, state) {
        final beaconId = state.beacon.id;
        Future<void> editUpdate(TimelineUpdate u) => _showEditAuthorUpdateSheet(
          context,
          beaconViewCubit,
          l10n,
          initial: u.content,
          updateId: u.id,
          createdAt: u.createdAt,
        );

        final tabBody = switch (idx) {
          kBeaconTabItems => ItemsTab(
            state: state,
            onOpenItemThread: onOpenItemDiscussion,
            focusItemId: focusItemId,
          ),
          kBeaconTabPeople => BeaconPeopleTabBody(
            state: state,
            beaconViewCubit: beaconViewCubit,
            l10n: l10n,
            focusUserId: focusUserId,
          ),
          kBeaconTabLog => BeaconActivityList(
            timeline: const [],
            beacon: state.beacon,
            isAuthorView: state.isBeaconMine,
            onEditTimelineUpdate: editUpdate,
            roomActivityEvents: state.roomActivityEvents,
            coordinationLogOnly: true,
            onTapCoordinationEvent: onTapCoordinationLogEvent,
            actors: {
              for (final p in state.roomParticipants) p.userId: p,
            },
          ),
          _ => const SizedBox.shrink(),
        };

        final tabPadding = idx == kBeaconTabPeople
            ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
            : kPaddingAll;

        final peopleTabBadge =
            state.isBeaconMine && state.unansweredHelpOffersCount > 0
            ? state.unansweredHelpOffersCount
            : null;
        final peopleTabSecondaryBadge =
            state.needCoordinationHelpOffersCount > 0
            ? state.needCoordinationHelpOffersCount
            : null;

        // Single CustomScrollView (no NestedScrollView) so the scroll position
        // is unified: there is no outer/inner coordinator that can let the
        // body scroll past its end when the tab content fits the viewport.
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          child: CustomScrollView(
            physics: const ClampingScrollPhysics(),
            slivers: [
              if (state.beacon.lineageParentBeaconId != null &&
                  state.beacon.lineageParentBeaconId!.isNotEmpty)
                SliverToBoxAdapter(
                  child: ColoredBox(
                    color: scheme.surface,
                    child: BeaconLineageParentLink(
                      parentBeaconId: state.beacon.lineageParentBeaconId!,
                    ),
                  ),
                ),
              SliverToBoxAdapter(
                child: ColoredBox(
                  color: scheme.surface,
                  child: BeaconOperationalHeaderCard(
                    state: state,
                    onAuthorTap: () =>
                        screenCubit.showProfile(state.beacon.author.id),
                    onUpdateStatus:
                        state.isAuthorOrSteward &&
                            state.beacon.lifecycle == BeaconLifecycle.open
                        ? () => unawaited(_showUpdateStatusSheet(context, state))
                        : null,
                    onPostUpdate:
                        state.isBeaconMine &&
                            state.beacon.lifecycle == BeaconLifecycle.open
                        ? () => unawaited(
                            _showPostAuthorUpdateSheet(
                              context,
                              beaconViewCubit,
                              l10n,
                            ),
                          )
                        : null,
                    onOfferHelp:
                        !state.isBeaconMine &&
                            state.beacon.lifecycle == BeaconLifecycle.open &&
                            !state.isHelpOffered &&
                            state.beacon.allowsNewHelpOfferAsNonAuthor
                        ? () => _runOfferHelpFlow(context, l10n)
                        : null,
                    onForward: () => unawaited(
                      _beaconViewOpenForwardThenMaybeNudgeOfferHelp(
                        context,
                        beaconViewCubit,
                        l10n,
                      ),
                    ),
                    onWatch:
                        !state.isBeaconMine &&
                            !state.isHelpOffered &&
                            state.inboxStatus == InboxItemStatus.needsMe
                        ? () => unawaited(beaconViewCubit.moveToWatching())
                        : null,
                    onStopWatching:
                        !state.isBeaconMine &&
                            !state.isHelpOffered &&
                            state.inboxStatus == InboxItemStatus.watching
                        ? () => unawaited(beaconViewCubit.stopWatching())
                        : null,
                    onViewChain: () =>
                        screenCubit.showForwardsGraphFor(beaconId),
                    onSwitchToPeopleTab: () => _setTab(kBeaconTabPeople),
                    onCloseBeacon:
                        state.isBeaconMine &&
                            state.beacon.lifecycle == BeaconLifecycle.open &&
                            state.closureActionPriority !=
                                ClosureActionPriority.hidden
                        ? () => unawaited(_beaconViewAuthorCloseFlow(context))
                        : null,
                    onOpenRoomSurface:
                        state.canNavigateBeaconRoom
                        ? onEnterRoomSurface
                        : null,
                    onOpenReview:
                        state.isBeaconMine &&
                            state.beacon.lifecycle != BeaconLifecycle.open &&
                            state.beacon.lifecycle !=
                                BeaconLifecycle.reviewOpen &&
                            state.beacon.lifecycle != BeaconLifecycle.deleted
                        ? () => unawaited(
                            context.router.pushPath(
                              '$kPathReviewContributions/$beaconId',
                            ),
                          )
                        : null,
                    onOpenLogTab:
                        state.isBeaconMine &&
                            state.beacon.lifecycle !=
                                BeaconLifecycle.reviewOpen
                        ? () => _setTab(kBeaconTabLog)
                        : null,
                    onEditNowLine: state.canCoordinateInBeaconRoom
                        ? () => unawaited(
                            showBeaconCurrentLineSheet(
                              context,
                              beaconId: beaconId,
                              initialText:
                                  state.beaconRoomCue?.currentLine ?? '',
                              onSaved: (line) => unawaited(
                                beaconViewCubit.refreshBeaconRoomCue(
                                  savedCurrentLine: line,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PinnedSegmentBarDelegate(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kSpacingMedium,
                    ),
                    child: Align(
                      child: SizedBox(
                        width: double.infinity,
                        child: BlocBuilder<ItemsTabCubit, ItemsTabState>(
                          buildWhen: (p, c) =>
                              p.openItems != c.openItems ||
                              p.unreadDiscussionCount !=
                                  c.unreadDiscussionCount,
                          builder: (context, itemsTabState) {
                            final itemsTabBadge =
                                itemsTabState.unreadDiscussionCount > 0
                                ? itemsTabState.unreadDiscussionCount
                                : null;
                            return TenturaUnderlineTabs(
                              tabs: [
                                l10n.labelBeaconTabItems,
                                l10n.labelBeaconTabPeople,
                                l10n.labelBeaconTabLog,
                              ],
                              selectedIndex: idx,
                              onChanged: _setTab,
                              badges: [
                                itemsTabBadge,
                                peopleTabBadge,
                                null,
                              ],
                              secondaryBadges: [
                                null,
                                peopleTabSecondaryBadge,
                                null,
                              ],
                              attentionIndex: kBeaconTabPeople,
                              attentionActive: peopleTabAttentionActive,
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverPadding(
                key: ValueKey<int>(idx),
                padding: tabPadding,
                sliver: SliverToBoxAdapter(child: tabBody),
              ),
              // Pads any remaining viewport so short tab content cannot be
              // scrolled out of view; collapses to zero when content overflows.
              const SliverFillRemaining(
                hasScrollBody: false,
                child: SizedBox.shrink(),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// Pinned tab bar: fixed height so layoutExtent matches paintExtent under
/// NestedScrollView (avoids invalid SliverGeometry on web).
class _PinnedSegmentBarDelegate extends SliverPersistentHeaderDelegate {
  _PinnedSegmentBarDelegate({required this.child});

  final Widget child;

  static const double _barHeight = 48;

  @override
  double get minExtent => _barHeight;

  @override
  double get maxExtent => _barHeight;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: overlapsContent ? 0.5 : 0,
      child: SizedBox(
        height: _barHeight,
        width: double.infinity,
        child: child,
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PinnedSegmentBarDelegate oldDelegate) {
    return child != oldDelegate.child;
  }
}

Future<void> _showPostAuthorUpdateSheet(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  final text = await showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AuthorUpdateComposerSheet(
      title: l10n.postUpdateCTA,
      hintText: l10n.beaconUpdateComposerHint,
      submitText: l10n.postUpdateCTA,
      footerHint: l10n.beaconUpdateEditWindowHint,
    ),
  );
  final t = text?.trim();
  if (t != null && t.isNotEmpty && context.mounted) {
    await cubit.postAuthorUpdate(t);
  }
}

Future<void> _showEditAuthorUpdateSheet(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n, {
  required String initial,
  required String updateId,
  required DateTime createdAt,
}) async {
  if (!_authorUpdateEditableNow(createdAt)) {
    if (context.mounted) {
      showSnackBar(
        context,
        isError: true,
        text: l10n.beaconUpdateEditExpired,
      );
    }
    return;
  }
  final text = await showModalBottomSheet<String?>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => _AuthorUpdateComposerSheet(
      title: l10n.editUpdateCTA,
      hintText: l10n.beaconUpdateComposerHint,
      submitText: l10n.buttonSaveChanges,
      footerHint: l10n.beaconUpdateEditWindowHint,
      initialText: initial,
    ),
  );

  final t = text?.trim();
  if (t != null && t.isNotEmpty && t != initial && context.mounted) {
    await cubit.editAuthorUpdate(id: updateId, content: t);
  }
}

class _AuthorUpdateComposerSheet extends StatefulWidget {
  const _AuthorUpdateComposerSheet({
    required this.title,
    required this.hintText,
    required this.submitText,
    required this.footerHint,
    this.initialText,
  });

  final String title;
  final String hintText;
  final String submitText;
  final String footerHint;
  final String? initialText;

  @override
  State<_AuthorUpdateComposerSheet> createState() =>
      _AuthorUpdateComposerSheetState();
}

class _AuthorUpdateComposerSheetState
    extends State<_AuthorUpdateComposerSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.only(
        left: kSpacingSmall,
        right: kSpacingSmall,
        top: kSpacingMedium,
        bottom: bottom + kSpacingMedium,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.title, style: theme.textTheme.titleMedium),
          const SizedBox(height: kSpacingSmall),
          TextField(
            controller: _controller,
            maxLines: 6,
            maxLength: kDescriptionMaxLength,
            decoration: InputDecoration(hintText: widget.hintText),
          ),
          const SizedBox(height: kSpacingSmall),
          Text(
            widget.footerHint,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: kSpacingSmall),
          FilledButton(
            onPressed: () {
              final t = _controller.text.trim();
              if (t.isEmpty) return;
              Navigator.of(context).pop(t);
            },
            child: Text(widget.submitText),
          ),
        ],
      ),
    );
  }
}
