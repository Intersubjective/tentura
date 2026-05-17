import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/items_tab_state.dart';
import 'package:tentura/features/beacon_view/domain/beacon_view_entry_source.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon_room/ui/widget/beacon_room_self_ask_sheet.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_evaluation_hooks.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';

import '../bloc/beacon_view_cubit.dart';
import '../dialog/help_offer_message_dialog.dart';
import '../widget/activity_list.dart';
import '../widget/beacon_operational_header_card.dart';
import '../widget/beacon_anchor_status.dart';
import '../widget/beacon_view_app_bar_title.dart';
import '../widget/beacon_people_participant_card.dart';
import '../widget/help_offer_tile.dart';
import '../widget/coordination_response_bottom_sheet.dart';
import '../util/help_offer_types_wire.dart';
import '../widget/beacon_prepared_ask_sheet.dart';
import '../widget/beacon_prepared_blocker_sheet.dart';
import '../widget/items_tab.dart';
import '../widget/unified_forward_row.dart';

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
  final state = cubit.state;
  if (!state.beacon.isListed) {
    await cubit.toggleLifecycle();
    return;
  }
  final summary = buildClosureConfirmationSummary(state);
  await showBeaconCloseConfirmSheet(
    context: context,
    summary: summary,
    isLoading: cubit.state.isLoading,
    onCloseBeacon: () async {
      Navigator.of(context).pop();
      await cubit.toggleLifecycle();
    },
    onOpenPeople: () {
      Navigator.of(context).pop();
      onOpenPeopleTab();
    },
    onPostUpdate: () async {
      Navigator.of(context).pop();
      await _showPostAuthorUpdateSheet(context, cubit, l10n);
    },
    onResolveRoom: state.canNavigateBeaconRoom
        ? () {
            Navigator.of(context).pop();
            onEnterRoomSurface();
          }
        : null,
  );
}

bool _canShowSelfAsk(BeaconViewState state) {
  final b = state.beacon;
  if (b.lifecycle != BeaconLifecycle.open) return false;
  return state.isAuthorOrSteward || state.hasRoomAdmission;
}

Widget _beaconViewAppBarOverflow({
  required BuildContext context,
  required BeaconViewState state,
  required BeaconViewCubit cubit,
  required ScreenCubit screenCubit,
  required L10n l10n,
  required Future<void> Function() onAuthorListedOpenClose,
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
      onToggleLifecycle: _authorLifecycleToggleEnabled(state)
          ? () async {
              if (!context.mounted) return;
              final b = state.beacon;
              if (b.lifecycle == BeaconLifecycle.open && b.isListed) {
                await onAuthorListedOpenClose();
                return;
              }
              await cubit.toggleLifecycle();
            }
          : null,
      onEdit: b.lifecycle == BeaconLifecycle.open
          ? () => unawaited(
              context.router.pushPath(
                '$kPathBeaconNew?$kQueryBeaconEditId=$beaconId',
              ),
            )
          : null,
      onPrepareAsk: b.lifecycle == BeaconLifecycle.open
          ? () => unawaited(
              showPreparedAskEditorSheet(
                context,
                beaconId: beaconId,
                onSaved: () => unawaited(
                  context.read<ItemsTabCubit>().fetch(),
                ),
              ),
            )
          : null,
      onPrepareBlocker: b.lifecycle == BeaconLifecycle.open
          ? () => unawaited(
              showPreparedBlockerEditorSheet(
                context,
                beaconId: beaconId,
                onSaved: () => unawaited(
                  context.read<ItemsTabCubit>().fetch(),
                ),
              ),
            )
          : null,
      onSelfAsk: _canShowSelfAsk(state)
          ? () => unawaited(
              showBeaconRoomSelfAskSheet(
                context,
                beaconId: beaconId,
                onSaved: () => unawaited(
                  context.read<ItemsTabCubit>().fetch(),
                ),
              ),
            )
          : null,
      onForward: () => unawaited(
        _beaconViewOpenForwardThenMaybeNudgeOfferHelp(context, cubit, l10n),
      ),
      onForwardsGraph: () => screenCubit.showForwardsGraphFor(beaconId),
      onDraftReview: state.showDraftEvaluationCta
          ? () => unawaited(
              context.router.pushPath(
                '$kPathReviewContributions/$beaconId?draft=true',
              ),
            )
          : null,
      onDelete: () async {
        if (!context.mounted) return;
        if (await BeaconDeleteDialog.show(context) ?? false) {
          if (!context.mounted) return;
          await cubit.delete(beaconId);
        }
      },
    );
  }

  return BeaconOverflowMenu(
    beacon: b,
    onSelfAsk: _canShowSelfAsk(state)
        ? () => unawaited(
            showBeaconRoomSelfAskSheet(
              context,
              beaconId: beaconId,
              onSaved: () => unawaited(
                context.read<ItemsTabCubit>().fetch(),
              ),
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

  RoomCubit? _roomCubit;
  ItemsTabCubit? _itemsTabCubit;
  bool _didApplyFetchResolution = false;
  String? _bannerMessage;

  /// True after the user leaves the room surface until they open it again.
  /// Prevents [didUpdateWidget] from re-opening room while `?tab=room` is still
  /// on the URL briefly after [replacePath] / history sync.
  bool _userDismissedRoomSurface = false;

  bool _roomExitInProgress = false;

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

  /// Drop the embedded room cubit so the next room visit re-reads the
  /// server last-seen watermark for the unread divider.
  void _releaseEmbeddedRoomCubit() {
    final c = _roomCubit;
    if (c == null) return;
    _roomCubit = null;
    if (!c.isClosed) {
      unawaited(c.close());
    }
  }

  @override
  void didUpdateWidget(BeaconViewScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _userDismissedRoomSurface = false;
      _roomExitInProgress = false;
    }
    final wasRoom = _roomFromRouteParams(oldWidget);
    final isRoom = _roomFromRouteParams(widget);
    if (wasRoom && !isRoom && _showRoomSurface) {
      _exitRoomSurface(fromRouteSync: true);
    } else if (!wasRoom &&
        isRoom &&
        !_showRoomSurface &&
        !_userDismissedRoomSurface) {
      _applyRoomSurfaceState(open: true);
    }
  }

  @override
  void dispose() {
    _releaseEmbeddedRoomCubit();
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
        _roomCubit ??= RoomCubit(beaconId: widget.id);
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
        _roomCubit ??= RoomCubit(beaconId: widget.id);
      });
    } else {
      if (!_showRoomSurface) return;
      if (!fromRouteSync) {
        _userDismissedRoomSurface = true;
      }
      // Hide room before [clearRoomUnread] — its emit rebuilds this screen and
      // build() must not recreate [RoomCubit] via `_roomCubit ??=` while exiting.
      setState(() => _showRoomSurface = false);
      _releaseEmbeddedRoomCubit();
      context.read<BeaconViewCubit>().clearRoomUnread();
    }
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
    if (!context.read<BeaconViewCubit>().state.canNavigateBeaconRoom) {
      return;
    }
    // Push a dedicated `?tab=room` route instead of also embedding room on the
    // route below — otherwise back pops the top route but leaves a live
    // [RoomCubit] + `_showRoomSurface` on the underlying beacon view.
    if (!_roomFromRouteParams(widget)) {
      _userDismissedRoomSurface = false;
      final roomPath = _beaconViewPath(viewTab: 'room');
      // Web: replace in place so browser back + PopScope do not fight a pushed
      // history entry ([usesPathAsKey] keeps one stack page for this beacon).
      unawaited(
        kIsWeb
            ? context.router.replacePath(roomPath)
            : context.router.pushPath(roomPath),
      );
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
    unawaited(context.router.push(ItemDiscussionRoute(item: item)));
  }

  void _exitRoomSurface({bool fromRouteSync = false}) {
    if (_roomExitInProgress) return;

    if (fromRouteSync) {
      if (_showRoomSurface) {
        _applyRoomSurfaceState(open: false, fromRouteSync: true);
      }
      return;
    }

    _roomExitInProgress = true;
    if (_showRoomSurface) {
      _applyRoomSurfaceState(open: false);
    }

    // Never [maybePop] here — with [usesPathAsKey] and PopScope vetoing browser
    // back, maybePop fights popstate and can freeze the tab. Strip `?tab=room`
    // via replacePath so the user stays on the operational beacon view.
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
          _releaseEmbeddedRoomCubit();
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

          final activeHelpOfferCount = state.helpOffers
              .where((c) => !c.isWithdrawn)
              .length;
          final (appBarStatusLine, appBarStatusTone) = _showRoomSurface
              ? (state.roomUnreadCount > 0
                    ? (
                        'ROOM · Unread: ${state.roomUnreadCount}',
                        TenturaTone.info,
                      )
                    : ('ROOM · UP-TO-DATE', TenturaTone.neutral))
              : (
                  beaconAnchorStatusLineShort(
                    state.beacon,
                    activeHelpOfferCount,
                  ),
                  beaconAnchorStatusTone(state.beacon.coordinationStatus),
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
                    child: const BeaconRoomSurface(),
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
    if (!peopleTabAttentionActive) return;
    onPeopleTabAttentionCleared();
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
        BeaconCoordinationStatus.helpOffersWaitingForReview.smallintValue,
        l10n.coordinationWaitingForReview,
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
          p.beaconRoomCue?.currentPlan != c.beaconRoomCue?.currentPlan ||
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
          ),
          kBeaconTabPeople => _HelpOffersTabBody(
            state: state,
            beaconViewCubit: beaconViewCubit,
            l10n: l10n,
          ),
          kBeaconTabLog => BeaconActivityList(
            timeline: const [],
            beacon: state.beacon,
            isAuthorView: state.isBeaconMine,
            onEditTimelineUpdate: editUpdate,
            roomActivityEvents: state.roomActivityEvents,
            coordinationLogOnly: true,
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
                            state.beacon.lifecycle != BeaconLifecycle.deleted
                        ? () => unawaited(
                            context.router.pushPath(
                              '$kPathReviewContributions/$beaconId',
                            ),
                          )
                        : null,
                    onOpenLogTab: state.isBeaconMine ? () => _setTab(kBeaconTabLog) : null,
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

class _HelpOffersTabBody extends StatelessWidget {
  const _HelpOffersTabBody({
    required this.state,
    required this.beaconViewCubit,
    required this.l10n,
  });

  final BeaconViewState state;
  final BeaconViewCubit beaconViewCubit;
  final L10n l10n;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final beacon = state.beacon;
    final active = state.helpOffers
        .where((c) => !c.isWithdrawn)
        .toList(growable: false);
    final withdrawn = state.helpOffers
        .where((c) => c.isWithdrawn)
        .toList(growable: false);

    final stewards = state.roomParticipants
        .where((p) => p.role == BeaconParticipantRoleBits.steward)
        .toList(growable: false);

    final admittedMembers = state.canNavigateBeaconRoom
        ? state.roomParticipants
            .where(
              (p) =>
                  p.roomAccess == RoomAccessBits.admitted &&
                  p.role != BeaconParticipantRoleBits.author &&
                  p.role != BeaconParticipantRoleBits.steward &&
                  p.userId != beacon.author.id,
            )
            .toList(growable: false)
        : const <BeaconParticipant>[];

    final needCoordList = active
        .where(
          (c) =>
              c.coordinationResponse ==
              CoordinationResponseType.needCoordination,
        )
        .toList(growable: false);
    final otherActive =
        active
            .where(
              (c) =>
                  c.coordinationResponse !=
                  CoordinationResponseType.needCoordination,
            )
            .toList(growable: false)
          ..sort((a, b) {
            int p(CoordinationResponseType? r) => switch (r) {
              CoordinationResponseType.useful => 0,
              CoordinationResponseType.overlapping => 1,
              _ => 2,
            };
            final cmp = p(
              a.coordinationResponse,
            ).compareTo(p(b.coordinationResponse));
            if (cmp != 0) return cmp;
            return a.user.title.compareTo(b.user.title);
          });

    HelpOfferTile helpOfferTile(TimelineHelpOffer c) {
      return HelpOfferTile(
        helpOffer: c,
        beaconId: beacon.id,
        beaconAuthorId: beacon.author.id,
        isMine: c.user.id == state.myProfile.id,
        isAuthorView: state.isAuthorOrSteward,
        onAuthorTapCoordination: state.isAuthorOrSteward && !c.isWithdrawn
            ? () => unawaited(
                showCoordinationResponseBottomSheet(
                  context: context,
                  offerUserTitle: c.user.title,
                  initialResponse: c.coordinationResponse,
                  offerUserAdmittedToRoom: state.roomParticipants.any(
                    (p) =>
                        p.userId == c.user.id &&
                        p.roomAccess == RoomAccessBits.admitted,
                  ),
                  onSave:
                      ({
                        required responseTypeSmallint,
                        required inviteToRoom,
                        required removeFromRoom,
                      }) => beaconViewCubit.setCoordinationResponse(
                        offerUserId: c.user.id,
                        responseType: responseTypeSmallint,
                        inviteToRoom: inviteToRoom,
                        removeFromRoom: removeFromRoom,
                      ),
                ),
              )
            : null,
        onEdit: c.user.id == state.myProfile.id && !c.isWithdrawn
            ? () async {
                final outcome = await HelpOfferMessageDialog.show(
                  context,
                  title: l10n.beaconHeaderUpdateHelpOffer,
                  hintText: l10n.hintOfferHelpMessage,
                  initialText: c.message,
                  allowEmptyMessage: true,
                  showHelpTypeChips: true,
                  initialHelpTypeSlugs: helpOfferStoredHelpTypeSlugs(
                    c.helpType,
                  ),
                  automaticSlugs: beacon.needs,
                );
                if (outcome != null && context.mounted) {
                  await beaconViewCubit.offerHelp(
                    message: outcome.message,
                    helpTypes: normalizeOfferHelpTypesWire(
                      outcome.helpTypesWire,
                    ),
                  );
                }
              }
            : null,
        onWithdraw:
            c.user.id == state.myProfile.id &&
                !c.isWithdrawn &&
                beacon.allowsWithdrawWhileHelpOffered
            ? () async {
                final outcome = await HelpOfferMessageDialog.show(
                  context,
                  title: l10n.dialogWithdrawHelpOfferTitle,
                  hintText: l10n.hintWithdrawReason,
                  allowEmptyMessage: true,
                  requireWithdrawReason: true,
                );
                if (outcome?.withdrawReasonWire != null && context.mounted) {
                  await beaconViewCubit.withdraw(
                    message: outcome!.message,
                    withdrawReason: outcome.withdrawReasonWire!,
                  );
                }
              }
            : null,
      );
    }

    final sectionHeaderStyle = theme.textTheme.titleSmall!.copyWith(
      color: theme.colorScheme.onSurface,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BeaconEvaluationHooks(
          beaconId: beacon.id,
          lifecycle: beacon.lifecycle,
        ),
        const SizedBox(height: 12),
        Text(l10n.beaconPeopleLensAuthorHeading, style: sectionHeaderStyle),
        const SizedBox(height: 8),
        GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: () =>
              context.read<ScreenCubit>().showProfile(beacon.author.id),
          child: Row(
            children: [
              SelfAwareAvatar(
                profile: beacon.author,
                size: 36,
                withRating: beacon.author.id != state.myProfile.id,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: BlocBuilder<ProfileCubit, ProfileState>(
                  buildWhen: (p, c) => p.profile.id != c.profile.id,
                  builder: (context, profileState) {
                    final base = beaconCardMetadataLineTextStyle(theme);
                    final isSelf = SelfUserHighlight.profileIsSelf(
                      beacon.author,
                      profileState.profile.id,
                    );
                    return Text(
                      SelfUserHighlight.displayName(
                        l10n,
                        beacon.author,
                        profileState.profile.id,
                      ),
                      style: SelfUserHighlight.nameStyle(theme, base, isSelf),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        if (stewards.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.beaconPeopleLensStewardsHeading, style: sectionHeaderStyle),
          const SizedBox(height: 8),
          for (var i = 0; i < stewards.length; i++) ...[
            if (i != 0) const SizedBox(height: 8),
            BeaconPeopleParticipantCard(
              beacon: beacon,
              participant: stewards[i],
              helpOffers: state.helpOffers,
            ),
          ],
        ],
        if (admittedMembers.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(l10n.beaconPeopleLensRoomMembersHeading, style: sectionHeaderStyle),
          const SizedBox(height: 8),
          for (var i = 0; i < admittedMembers.length; i++) ...[
            if (i != 0) const SizedBox(height: 8),
            BeaconPeopleParticipantCard(
              beacon: beacon,
              participant: admittedMembers[i],
              helpOffers: state.helpOffers,
            ),
          ],
        ],
        if (needCoordList.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.beaconPeopleLensNeedsAttentionHeading,
            style: sectionHeaderStyle,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < needCoordList.length; i++) ...[
            if (i != 0) const SizedBox(height: 12),
            helpOfferTile(needCoordList[i]),
          ],
        ],
        if (otherActive.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            '${l10n.beaconPeopleLensActiveHelpersHeading} (${otherActive.length})',
            style: sectionHeaderStyle,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < otherActive.length; i++) ...[
            if (i != 0) const SizedBox(height: 12),
            helpOfferTile(otherActive[i]),
          ],
        ],
        const SizedBox(height: 16),
        if (state.forwardsLoaded) ...[
          Builder(
            builder: (context) {
              final edges = state.viewerForwardEdges;
              final hasAny = edges.isNotEmpty;
              final viewerId = state.myProfile.id;
              final feedRows = <Widget>[
                for (final e in edges)
                  e.sender.id == viewerId
                      ? UnifiedForwardRow.outgoing(
                          edge: e,
                          viewerUserId: viewerId,
                          helpOffered: state.involvementHelpOfferedIds,
                          watching: state.involvementWatchingIds,
                          onward: state.involvementOnwardForwarderIds,
                          reasonSlugs: state.forwardReasonSlugs[
                                  '${e.sender.id}__${e.recipient.id}'] ??
                              const [],
                        )
                      : UnifiedForwardRow.inbound(
                          sender: e.sender,
                          note: e.note,
                          viewerUserId: viewerId,
                          reasonSlugs: state.forwardReasonSlugs[
                                  '${e.sender.id}__${e.recipient.id}'] ??
                              const [],
                        ),
              ];
              if (hasAny) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${l10n.labelForwards} (${edges.length})',
                      style: sectionHeaderStyle,
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < feedRows.length; i++) ...[
                          if (i > 0) const SizedBox(height: kSpacingMedium),
                          feedRows[i],
                        ],
                      ],
                    ),
                  ],
                );
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${l10n.labelForwards} (0)',
                    style: sectionHeaderStyle,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    l10n.beaconForwardsEmpty,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              );
            },
          ),
        ] else if (state.forwardsLoading)
          const Center(
            child: Padding(
              padding: kPaddingSmallV,
              child: CircularProgressIndicator.adaptive(),
            ),
          )
        else
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.forward_to_inbox),
              label: Text(l10n.beaconPeopleShowForwards),
              onPressed: () => unawaited(beaconViewCubit.loadForwards()),
            ),
          ),
        if (withdrawn.isNotEmpty) ...[
          if (active.isNotEmpty) const SizedBox(height: 12),
          ExpansionTile(
            title: Text(l10n.beaconShowWithdrawn(withdrawn.length)),
            children: [
              for (var j = 0; j < withdrawn.length; j++) ...[
                if (j != 0) const SizedBox(height: 12),
                HelpOfferTile(
                  helpOffer: withdrawn[j],
                  beaconId: beacon.id,
                  beaconAuthorId: beacon.author.id,
                  isMine: withdrawn[j].user.id == state.myProfile.id,
                  isAuthorView: state.isAuthorOrSteward,
                ),
              ],
            ],
          ),
        ],
      ],
    );
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
