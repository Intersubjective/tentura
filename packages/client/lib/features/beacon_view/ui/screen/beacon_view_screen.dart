import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_view/domain/beacon_surface_mode.dart';
import 'package:tentura/features/beacon_view/domain/beacon_view_entry_source.dart';
import 'package:tentura/features/beacon_view/domain/beacon_view_surface_resolver.dart';
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
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/sheet/beacon_close_confirm_sheet.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_closure_readiness.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_evaluation_hooks.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';

import '../bloc/beacon_view_cubit.dart';
import '../dialog/commitment_message_dialog.dart';
import '../widget/activity_list.dart';
import '../widget/beacon_operational_header_card.dart';
import '../widget/beacon_anchor_status.dart';
import '../widget/beacon_view_app_bar_title.dart';
import '../widget/commitment_tile.dart';
import '../widget/coordination_response_bottom_sheet.dart';
import '../util/commitment_help_types_wire.dart';
import '../widget/overview/beacon_overview_tab.dart';
import '../widget/unified_forward_row.dart';

bool _beaconPeopleTabAttentionQueryTruthy(String? v) {
  if (v == null || v.isEmpty) return false;
  final s = v.toLowerCase();
  return s == '1' || s == 'true' || s == 'yes';
}

/// Query [kQueryBeaconViewTab]: `overview` | `commitments` | `timeline` (alias: `activity`; legacy: `details`, `forwards`).
int _beaconViewTabIndex(String? viewTab) {
  switch (viewTab) {
    case 'commitments':
      return 1;
    case 'activity':
    case 'timeline':
      return 2;
    case 'details':
    case 'forwards':
    case 'overview':
    default:
      return 0;
  }
}

bool _forwardInPrimaryCta(BeaconViewState state) {
  final b = state.beacon;
  if (state.isBeaconMine || b.lifecycle != BeaconLifecycle.open) {
    return false;
  }
  if (!state.isCommitted && b.allowsNewCommitAsNonAuthor) {
    return true;
  }
  if (state.isCommitted && !b.allowsWithdrawWhileCommitted) {
    return true;
  }
  return false;
}

bool _hideCommitWithdrawFromOverflow(BeaconViewState state) {
  final b = state.beacon;
  if (state.isBeaconMine || b.lifecycle != BeaconLifecycle.open) {
    return false;
  }
  if (!state.isCommitted && b.allowsNewCommitAsNonAuthor) {
    return true;
  }
  if (state.isCommitted && b.allowsWithdrawWhileCommitted) {
    return true;
  }
  return false;
}

const _beaconAuthorUpdateEditWindow = Duration(hours: 1);

/// Initial commit dialog + [BeaconViewCubit.commit] (not update-commitment).
Future<void> _beaconViewRunInitialCommitDialog(
  BuildContext context,
  BeaconViewCubit cubit,
  L10n l10n,
) async {
  if (!context.mounted) return;
  final useCommitAnyway =
      cubit.state.beacon.coordinationStatus ==
      BeaconCoordinationStatus.enoughHelpCommitted;
  final outcome = await CommitmentMessageDialog.show(
    context,
    title: useCommitAnyway
        ? l10n.dialogCommitAnywayTitle
        : l10n.dialogCommitTitle,
    hintText: l10n.hintCommitMessage,
    allowEmptyMessage: true,
    showHelpTypeChips: true,
  );
  if (outcome != null && context.mounted) {
    await cubit.commit(
      message: outcome.message,
      helpTypes: outcome.helpTypesWire,
    );
  }
}

Future<void> _beaconViewOpenForwardThenMaybeNudgeCommit(
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
  if (s.isCommitted ||
      s.isBeaconMine ||
      !s.beacon.allowsNewCommitAsNonAuthor ||
      s.beacon.lifecycle != BeaconLifecycle.open) {
    return;
  }
  showSnackBar(
    context,
    text: l10n.nudgeCommitAfterForward,
    action: SnackBarAction(
      label: l10n.labelCommit,
      onPressed: () => unawaited(
        _beaconViewRunInitialCommitDialog(context, cubit, l10n),
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

Future<void> _beaconViewRunAuthorCloseSheet({
  required BuildContext context,
  required BeaconViewCubit cubit,
  required L10n l10n,
  required void Function() onOpenPeopleTab,
  required void Function(BeaconViewState state) onToggleRoomSurface,
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
            onToggleRoomSurface(state);
          }
        : null,
  );
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
  final hideCommitWithdraw = _hideCommitWithdrawFromOverflow(state);

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
      onForward: () => unawaited(
        _beaconViewOpenForwardThenMaybeNudgeCommit(context, cubit, l10n),
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
    onCommit:
        !hideCommitWithdraw &&
            !state.isCommitted &&
            b.allowsNewCommitAsNonAuthor
        ? () async {
            await _beaconViewRunInitialCommitDialog(context, cubit, l10n);
          }
        : null,
    onWithdraw:
        !hideCommitWithdraw &&
            state.isCommitted &&
            b.allowsWithdrawWhileCommitted
        ? () async {
            if (!context.mounted) return;
            final outcome = await CommitmentMessageDialog.show(
              context,
              title: l10n.dialogWithdrawTitle,
              hintText: l10n.hintWithdrawReason,
              allowEmptyMessage: true,
              requireUncommitReason: true,
            );
            if (outcome?.uncommitReasonWire != null && context.mounted) {
              await cubit.withdraw(
                message: outcome!.message,
                uncommitReason: outcome.uncommitReasonWire!,
              );
            }
          }
        : null,
    onForward: hideOverflowForward
        ? null
        : () => unawaited(
            _beaconViewOpenForwardThenMaybeNudgeCommit(context, cubit, l10n),
          ),
    onForwardsGraph: () => screenCubit.showForwardsGraphFor(beaconId),
    onDraftReview: state.showDraftEvaluationCta
        ? () => unawaited(
            context.router.pushPath(
              '$kPathReviewContributions/$beaconId?draft=true',
            ),
          )
        : null,
    onWatch: !state.isCommitted && state.inboxStatus == InboxItemStatus.needsMe
        ? () => unawaited(cubit.moveToWatching())
        : null,
    onStopWatching:
        !state.isCommitted && state.inboxStatus == InboxItemStatus.watching
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

  /// `overview` | `commitments` | `activity` (legacy: `timeline`, `details`, `forwards`).
  final String? viewTab;

  /// With [viewTab]=`commitments`, truthy values pulse/highlight the People tab until interaction.
  final String? peopleTabAttention;

  /// `status` | `room` ([kBeaconSurfaceRoomQueryValue]).
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
  late BeaconSurfaceMode _surfaceMode;

  RoomCubit? _roomCubit;
  bool _didApplyFetchResolution = false;
  String? _bannerMessage;

  BeaconViewEntrySource get _normalizedEntry => normalizeBeaconViewEntry(
    isDeepLink: widget.isDeepLink,
    rawFromQuery: BeaconViewEntrySourceWire.parseQuery(widget.entry),
  );

  @override
  void initState() {
    super.initState();
    _tabIndex = _beaconViewTabIndex(widget.viewTab).clamp(0, 2);
    _peopleTabAttentionActive =
        _beaconPeopleTabAttentionQueryTruthy(widget.peopleTabAttention) &&
        _beaconViewTabIndex(widget.viewTab) == 1;
    final explicitRoom = explicitRoomSurfaceRequested(
      surfaceQuery: widget.surface,
      navigatedFromLegacyRoomPath: false,
      sharedLinkDestRoom: false,
    );
    _surfaceMode = explicitRoom
        ? BeaconSurfaceMode.room
        : BeaconSurfaceMode.status;
  }

  @override
  void dispose() {
    unawaited(_roomCubit?.close());
    super.dispose();
  }

  void _applyFetchResolution(BeaconViewState s) {
    if (!s.isSuccess || _didApplyFetchResolution) return;

    final explicitRoom = explicitRoomSurfaceRequested(
      surfaceQuery: widget.surface,
      navigatedFromLegacyRoomPath: false,
      sharedLinkDestRoom: false,
    );
    final explicitStatus = explicitStatusSurfaceRequested(
      surfaceQuery: widget.surface,
      viewTab: widget.viewTab,
    );

    final mode = resolveInitialBeaconSurfaceMode(
      entry: _normalizedEntry,
      hasRoomAccess: s.canNavigateBeaconRoom,
      explicitRoomRequested: explicitRoom,
      explicitStatusRequested: explicitStatus,
    );

    final roomDenied =
        !s.canNavigateBeaconRoom &&
        (explicitRoom ||
            _normalizedEntry == BeaconViewEntrySource.roomNotification);

    setState(() {
      _surfaceMode = mode;
      _bannerMessage = roomDenied
          ? L10n.of(context)!.beaconViewRoomAccessUnavailableBanner
          : null;
      _didApplyFetchResolution = true;
      if (mode == BeaconSurfaceMode.room && s.canNavigateBeaconRoom) {
        _roomCubit ??= RoomCubit(beaconId: widget.id);
      }
    });
  }

  void _onToggleSurface(BeaconViewState beaconState) {
    final next = _surfaceMode == BeaconSurfaceMode.status
        ? BeaconSurfaceMode.room
        : BeaconSurfaceMode.status;
    if (next == BeaconSurfaceMode.room && !beaconState.canNavigateBeaconRoom) {
      return;
    }
    if (next == BeaconSurfaceMode.status) {
      context.read<BeaconViewCubit>().clearRoomUnread();
    }
    setState(() {
      _surfaceMode = next;
      _bannerMessage = null;
      if (next == BeaconSurfaceMode.room) {
        _roomCubit ??= RoomCubit(beaconId: widget.id);
      }
    });
  }

  String _beaconViewSurfaceSwitchTooltip(
    BeaconViewState state,
    L10n l10n,
  ) {
    if (_surfaceMode == BeaconSurfaceMode.status) {
      final enabled = state.canNavigateBeaconRoom;
      return enabled
          ? l10n.beaconRoomOpen
          : (state.isRoomAdmissionBlocked
                ? (state.coordinationDeniesRoomAdmission
                      ? l10n.beaconRoomNoAdmission
                      : l10n.beaconRoomWaitingForApproval)
                : l10n.beaconViewRoomAccessUnavailableBanner);
    }
    return l10n.beaconViewSurfaceStatusAction;
  }

  @override
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final beaconViewCubit = context.read<BeaconViewCubit>();
    final l10n = L10n.of(context)!;
    return BlocListener<BeaconViewCubit, BeaconViewState>(
      listenWhen: (p, c) =>
          (!p.isSuccess && c.isSuccess) ||
          (_surfaceMode == BeaconSurfaceMode.room &&
              p.canNavigateBeaconRoom &&
              !c.canNavigateBeaconRoom),
      listener: (ctx, s) {
        if (!s.isSuccess) return;
        if (!ctx.mounted) return;
        if (_surfaceMode == BeaconSurfaceMode.room &&
            !s.canNavigateBeaconRoom) {
          setState(() {
            _surfaceMode = BeaconSurfaceMode.status;
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
            p.commitments != c.commitments ||
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
              state.commitments.isEmpty;

          final activeCommitCount = state.commitments
              .where((c) => !c.isWithdrawn)
              .length;
          final (appBarStatusLine, appBarStatusTone) = switch (_surfaceMode) {
            BeaconSurfaceMode.room =>
              state.roomUnreadCount > 0
                  ? (
                      'ROOM · Unread: ${state.roomUnreadCount}',
                      TenturaTone.info,
                    )
                  : ('ROOM · UP-TO-DATE', TenturaTone.neutral),
            _ => (
              beaconAnchorStatusLineShort(state.beacon, activeCommitCount),
              beaconAnchorStatusTone(state.beacon.coordinationStatus),
            ),
          };

          Widget body;
          if (showInitialLoading) {
            body = const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          } else if (_surfaceMode == BeaconSurfaceMode.room &&
              state.canNavigateBeaconRoom) {
            _roomCubit ??= RoomCubit(beaconId: widget.id);
            body = BlocProvider.value(
              value: _roomCubit!,
              child: const BeaconRoomSurface(),
            );
          } else {
            body = _BeaconOperationalScrollView(
              beaconViewCubit: beaconViewCubit,
              screenCubit: screenCubit,
              tabIndex: _tabIndex,
              onTabChanged: (i) => setState(() {
                _tabIndex = i;
                _peopleTabAttentionActive = false;
              }),
              peopleTabAttentionActive: _peopleTabAttentionActive,
              onPeopleTabAttentionCleared: () => setState(() {
                _peopleTabAttentionActive = false;
              }),
              onToggleRoomSurface: _onToggleSurface,
              onAuthorCloseRequested: (ctx) => _beaconViewRunAuthorCloseSheet(
                context: ctx,
                cubit: beaconViewCubit,
                l10n: L10n.of(ctx)!,
                onOpenPeopleTab: () => setState(() => _tabIndex = 1),
                onToggleRoomSurface: _onToggleSurface,
              ),
            );
          }

          return PopScope(
            canPop: _surfaceMode != BeaconSurfaceMode.room,
            onPopInvokedWithResult: (didPop, _) {
              if (didPop || !context.mounted) return;
              if (_surfaceMode == BeaconSurfaceMode.room) {
                _onToggleSurface(beaconViewCubit.state);
              }
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
                leading: _surfaceMode == BeaconSurfaceMode.room
                    ? IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        icon: const Icon(Icons.arrow_back_rounded),
                        onPressed: () => _onToggleSurface(state),
                      )
                    : const AutoLeadingWithFallback(fallbackPath: kPathHome),
                title: BeaconViewAppBarTitle(
                  beacon: state.beacon,
                  statusLine: appBarStatusLine,
                  statusTone: appBarStatusTone,
                  l10n: l10n,
                ),
                actions: [
                  if (!showInitialLoading &&
                      _surfaceMode == BeaconSurfaceMode.status &&
                      state.canNavigateBeaconRoom)
                    Badge(
                      isLabelVisible: state.roomUnreadCount > 0,
                      label: Text('${state.roomUnreadCount}'),
                      child: IconButton(
                        tooltip: _beaconViewSurfaceSwitchTooltip(state, l10n),
                        icon: const Icon(Icons.forum_rounded),
                        onPressed: () => _onToggleSurface(state),
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
                          onOpenPeopleTab: () => setState(() => _tabIndex = 1),
                          onToggleRoomSurface: _onToggleSurface,
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
    required this.onToggleRoomSurface,
    required this.onAuthorCloseRequested,
  });

  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  /// Pulse/highlight People tab until first pointer interaction or tab change.
  final bool peopleTabAttentionActive;
  final VoidCallback onPeopleTabAttentionCleared;

  final void Function(BeaconViewState state) onToggleRoomSurface;

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

  Future<void> _pickCoordinationStatus(BuildContext context) async {
    await showBeaconCoordinationStatusBottomSheet(
      context: context,
      onPick: (s) => unawaited(
        beaconViewCubit.setBeaconCoordinationStatus(
          BeaconCoordinationStatus.fromSmallint(s),
        ),
      ),
    );
  }

  Future<void> _beaconViewAuthorCloseFlow(BuildContext context) async {
    await onAuthorCloseRequested(context);
  }

  Future<void> _runCommitFlow(BuildContext context, L10n l10n) async {
    await _beaconViewRunInitialCommitDialog(
      context,
      beaconViewCubit,
      l10n,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final idx = tabIndex.clamp(0, 2);
    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      bloc: beaconViewCubit,
      buildWhen: (p, c) =>
          p.beacon != c.beacon ||
          p.beacon.coordinationStatus != c.beacon.coordinationStatus ||
          p.beacon.lifecycle != c.beacon.lifecycle ||
          p.timeline != c.timeline ||
          p.roomActivityEvents != c.roomActivityEvents ||
          p.commitments != c.commitments ||
          p.isCommitted != c.isCommitted ||
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
          p.unansweredCommitmentsCount != c.unansweredCommitmentsCount ||
          p.needCoordinationCommitmentsCount !=
              c.needCoordinationCommitmentsCount,
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
          0 => BeaconStatusDashboard(
            state: state,
            onViewAllCommitments: () => _setTab(1),
            onEditTimelineUpdate: editUpdate,
            onOpenRoom: state.canNavigateBeaconRoom
                ? () => onToggleRoomSurface(state)
                : null,
            onClosureCloseBeacon:
                state.isBeaconMine &&
                    state.beacon.lifecycle == BeaconLifecycle.open &&
                    state.closureActionPriority != ClosureActionPriority.hidden
                ? () => unawaited(_beaconViewAuthorCloseFlow(context))
                : null,
            onClosurePostUpdate:
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
            onClosureForward: () => unawaited(
              _beaconViewOpenForwardThenMaybeNudgeCommit(
                context,
                beaconViewCubit,
                l10n,
              ),
            ),
            onClosureOpenPeople: () => _setTab(1),
            onClosureResolveRoom:
                state.isBeaconMine && state.canNavigateBeaconRoom
                ? () => onToggleRoomSurface(state)
                : null,
          ),
          1 => _CommitmentsTabBody(
            state: state,
            beaconViewCubit: beaconViewCubit,
            l10n: l10n,
          ),
          _ => BeaconActivityList(
            timeline: state.timeline,
            beacon: state.beacon,
            isAuthorView: state.isBeaconMine,
            onEditTimelineUpdate: editUpdate,
            roomActivityEvents: state.roomActivityEvents,
          ),
        };

        final tabPadding = idx == 0
            ? const EdgeInsets.fromLTRB(
                kSpacingMedium,
                kSpacingSmall / 2,
                kSpacingMedium,
                kSpacingSmall,
              )
            : idx == 1
            ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
            : kPaddingAll;

        final peopleTabBadge =
            state.isBeaconMine && state.unansweredCommitmentsCount > 0
            ? state.unansweredCommitmentsCount
            : null;
        final peopleTabSecondaryBadge =
            state.needCoordinationCommitmentsCount > 0
            ? state.needCoordinationCommitmentsCount
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
                        state.isBeaconMine &&
                            state.beacon.lifecycle == BeaconLifecycle.open
                        ? () => unawaited(_pickCoordinationStatus(context))
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
                    onCommit:
                        !state.isBeaconMine &&
                            state.beacon.lifecycle == BeaconLifecycle.open &&
                            !state.isCommitted &&
                            state.beacon.allowsNewCommitAsNonAuthor
                        ? () => _runCommitFlow(context, l10n)
                        : null,
                    onForward: () => unawaited(
                      _beaconViewOpenForwardThenMaybeNudgeCommit(
                        context,
                        beaconViewCubit,
                        l10n,
                      ),
                    ),
                    onWatch:
                        !state.isBeaconMine &&
                            !state.isCommitted &&
                            state.inboxStatus == InboxItemStatus.needsMe
                        ? () => unawaited(beaconViewCubit.moveToWatching())
                        : null,
                    onStopWatching:
                        !state.isBeaconMine &&
                            !state.isCommitted &&
                            state.inboxStatus == InboxItemStatus.watching
                        ? () => unawaited(beaconViewCubit.stopWatching())
                        : null,
                    onViewChain: () =>
                        screenCubit.showForwardsGraphFor(beaconId),
                    onSwitchToPeopleTab: () => _setTab(1),
                    onCloseBeacon:
                        state.isBeaconMine &&
                            state.beacon.lifecycle == BeaconLifecycle.open &&
                            state.closureActionPriority !=
                                ClosureActionPriority.hidden
                        ? () => unawaited(_beaconViewAuthorCloseFlow(context))
                        : null,
                    onOpenRoomSurface:
                        state.isBeaconMine && state.canNavigateBeaconRoom
                        ? () => onToggleRoomSurface(state)
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
                    onOpenLogTab: state.isBeaconMine ? () => _setTab(2) : null,
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
                        child: TenturaUnderlineTabs(
                          tabs: [
                            l10n.labelBeaconTabStatus,
                            l10n.labelBeaconTabPeople,
                            l10n.labelBeaconTabLog,
                          ],
                          selectedIndex: idx,
                          onChanged: _setTab,
                          badges: [
                            null,
                            peopleTabBadge,
                            null,
                          ],
                          secondaryBadges: [
                            null,
                            peopleTabSecondaryBadge,
                            null,
                          ],
                          attentionIndex: 1,
                          attentionActive: peopleTabAttentionActive,
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

class _CommitmentsTabBody extends StatelessWidget {
  const _CommitmentsTabBody({
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
    final active = state.commitments
        .where((c) => !c.isWithdrawn)
        .toList(growable: false);
    final withdrawn = state.commitments
        .where((c) => c.isWithdrawn)
        .toList(growable: false);

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

    CommitmentTile commitmentTile(TimelineCommitment c) {
      return CommitmentTile(
        commitment: c,
        beaconId: beacon.id,
        beaconAuthorId: beacon.author.id,
        isMine: c.user.id == state.myProfile.id,
        isAuthorView: state.isBeaconMine,
        onAuthorTapCoordination: state.isBeaconMine && !c.isWithdrawn
            ? () => unawaited(
                showCoordinationResponseBottomSheet(
                  context: context,
                  commitUserTitle: c.user.title,
                  initialResponse: c.coordinationResponse,
                  commitUserAdmittedToRoom: state.roomParticipants.any(
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
                        commitUserId: c.user.id,
                        responseType: responseTypeSmallint,
                        inviteToRoom: inviteToRoom,
                        removeFromRoom: removeFromRoom,
                      ),
                ),
              )
            : null,
        onEdit: c.user.id == state.myProfile.id && !c.isWithdrawn
            ? () async {
                final outcome = await CommitmentMessageDialog.show(
                  context,
                  title: l10n.beaconHeaderUpdateCommitment,
                  hintText: l10n.hintCommitMessage,
                  initialText: c.message,
                  allowEmptyMessage: true,
                  showHelpTypeChips: true,
                  initialHelpTypeSlugs: commitmentStoredHelpTypeSlugs(
                    c.helpType,
                  ),
                  automaticSlugs: beacon.needs,
                );
                if (outcome != null && context.mounted) {
                  await beaconViewCubit.commit(
                    message: outcome.message,
                    helpTypes: normalizeCommitHelpTypesWire(
                      outcome.helpTypesWire,
                    ),
                  );
                }
              }
            : null,
        onWithdraw:
            c.user.id == state.myProfile.id &&
                !c.isWithdrawn &&
                beacon.allowsWithdrawWhileCommitted
            ? () async {
                final outcome = await CommitmentMessageDialog.show(
                  context,
                  title: l10n.dialogWithdrawTitle,
                  hintText: l10n.hintWithdrawReason,
                  allowEmptyMessage: true,
                  requireUncommitReason: true,
                );
                if (outcome?.uncommitReasonWire != null && context.mounted) {
                  await beaconViewCubit.withdraw(
                    message: outcome!.message,
                    uncommitReason: outcome.uncommitReasonWire!,
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
        if (needCoordList.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text(
            l10n.beaconPeopleLensNeedsAttentionHeading,
            style: sectionHeaderStyle,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < needCoordList.length; i++) ...[
            if (i != 0) const SizedBox(height: 12),
            commitmentTile(needCoordList[i]),
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
            commitmentTile(otherActive[i]),
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
                          committed: state.involvementCommittedIds,
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
                CommitmentTile(
                  commitment: withdrawn[j],
                  beaconId: beacon.id,
                  beaconAuthorId: beacon.author.id,
                  isMine: withdrawn[j].user.id == state.myProfile.id,
                  isAuthorView: state.isBeaconMine,
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
