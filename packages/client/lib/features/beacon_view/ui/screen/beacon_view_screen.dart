import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_view/domain/beacon_surface_mode.dart';
import 'package:tentura/features/beacon_view/domain/beacon_view_entry_source.dart';
import 'package:tentura/features/beacon_view/domain/beacon_view_surface_resolver.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_room_surface.dart';
import 'package:tentura/features/settings/domain/port/settings_repository_port.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
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

Widget _beaconViewAppBarOverflow({
  required BuildContext context,
  required BeaconViewState state,
  required BeaconViewCubit cubit,
  required ScreenCubit screenCubit,
  required L10n l10n,
}) {
  final b = state.beacon;
  final beaconId = b.id;
  final hideOverflowForward = _forwardInPrimaryCta(state);
  final hideCommitWithdraw = _hideCommitWithdrawFromOverflow(state);

  if (state.isBeaconMine) {
    return BeaconOverflowMenu(
      beacon: b,
      onGraph: b.myVote >= 0 ? () => screenCubit.showGraphFor(beaconId) : null,
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
      onToggleLifecycle: () async {
        if (!context.mounted) return;
        if (state.beacon.isListed) {
          if (await BeaconCloseConfirmDialog.show(context) != true) {
            return;
          }
          if (!context.mounted) return;
        }
        await cubit.toggleLifecycle();
      },
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
      onViewForwards: () => unawaited(
        context.router.pushPath('$kPathBeaconForwards/$beaconId'),
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
    onViewForwards: () => unawaited(
      context.router.pushPath('$kPathBeaconForwards/$beaconId'),
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
  BeaconSurfaceMode? _rememberedFromDb;
  bool _rememberedLoaded = false;
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
    _surfaceMode =
        explicitRoom ? BeaconSurfaceMode.room : BeaconSurfaceMode.status;
    unawaited(_loadRememberedSurfacePreference());
  }

  Future<void> _loadRememberedSurfacePreference() async {
    final wire = await GetIt.I<SettingsRepositoryPort>()
        .getBeaconLastSurfaceModeWire(widget.id);
    if (!mounted) return;
    setState(() {
      _rememberedFromDb = BeaconSurfaceModeWire.tryParse(wire);
      _rememberedLoaded = true;
    });
    final cubit = context.read<BeaconViewCubit>();
    if (cubit.state.isSuccess) {
      _applyFetchResolution(cubit.state);
    }
  }

  @override
  void dispose() {
    unawaited(_roomCubit?.close());
    super.dispose();
  }

  void _applyFetchResolution(BeaconViewState s) {
    if (!s.isSuccess || _didApplyFetchResolution) return;
    if (_normalizedEntry == BeaconViewEntrySource.myWork && !_rememberedLoaded) {
      return;
    }

    final explicitRoom = explicitRoomSurfaceRequested(
      surfaceQuery: widget.surface,
      navigatedFromLegacyRoomPath: false,
      sharedLinkDestRoom: false,
    );
    final explicitStatus = explicitStatusSurfaceRequested(
      surfaceQuery: widget.surface,
      viewTab: widget.viewTab,
    );
    final remembered = _normalizedEntry == BeaconViewEntrySource.myWork
        ? _rememberedFromDb
        : null;

    final mode = resolveInitialBeaconSurfaceMode(
      entry: _normalizedEntry,
      hasRoomAccess: s.canNavigateBeaconRoom,
      explicitRoomRequested: explicitRoom,
      explicitStatusRequested: explicitStatus,
      rememberedMode: remembered,
    );

    final roomDenied = !s.canNavigateBeaconRoom &&
        (explicitRoom ||
            _normalizedEntry == BeaconViewEntrySource.roomNotification ||
            (_normalizedEntry == BeaconViewEntrySource.myWork &&
                remembered == BeaconSurfaceMode.room));

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
    setState(() {
      _surfaceMode = next;
      _bannerMessage = null;
      if (next == BeaconSurfaceMode.room) {
        _roomCubit ??= RoomCubit(beaconId: widget.id);
      }
    });
    unawaited(
      GetIt.I<SettingsRepositoryPort>().setBeaconLastSurfaceModeWire(
        widget.id,
        next.wire,
      ),
    );
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
            _bannerMessage = L10n.of(ctx)!.beaconViewRoomAccessUnavailableBanner;
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
            p.coordinationDeniesRoomAdmission != c.coordinationDeniesRoomAdmission,
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
            BeaconSurfaceMode.room => state.roomUnreadCount > 0
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
              child: BeaconRoomSurface(beaconState: state),
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
            );
          }

          return Scaffold(
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
              leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
              title: BeaconViewAppBarTitle(
                beacon: state.beacon,
                statusLine: appBarStatusLine,
                statusTone: appBarStatusTone,
                l10n: l10n,
                onTap: !showInitialLoading &&
                        (_surfaceMode == BeaconSurfaceMode.room ||
                            state.canNavigateBeaconRoom)
                    ? () => _onToggleSurface(state)
                    : null,
                tooltipMessage: !showInitialLoading
                    ? _beaconViewSurfaceSwitchTooltip(state, l10n)
                    : null,
                roomUnreadBadgeCount:
                    !showInitialLoading &&
                            _surfaceMode == BeaconSurfaceMode.status &&
                            state.canNavigateBeaconRoom &&
                            state.roomUnreadCount > 0
                        ? state.roomUnreadCount
                        : null,
              ),
              actions: [
                _beaconViewAppBarOverflow(
                  context: context,
                  state: state,
                  cubit: beaconViewCubit,
                  screenCubit: screenCubit,
                  l10n: l10n,
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
                        onPressed: () => setState(() => _bannerMessage = null),
                        child: Text(l10n.beaconViewBannerDismiss),
                      ),
                    ],
                  ),
                Expanded(child: body),
              ],
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
  });

  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;
  final int tabIndex;
  final ValueChanged<int> onTabChanged;

  /// Pulse/highlight People tab until first pointer interaction or tab change.
  final bool peopleTabAttentionActive;
  final VoidCallback onPeopleTabAttentionCleared;

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
          p.factCards != c.factCards ||
          p.roomParticipants.length != c.roomParticipants.length ||
          (p.roomParticipants
                  .map((e) => '${e.userId}|${e.userTitle}|${e.nextMoveText}')
                  .join() !=
              c.roomParticipants
                  .map((e) => '${e.userId}|${e.userTitle}|${e.nextMoveText}')
                  .join()) ||
          p.beaconRoomCue?.lastRoomMeaningfulChange !=
              c.beaconRoomCue?.lastRoomMeaningfulChange ||
          p.beaconRoomCue?.currentPlan != c.beaconRoomCue?.currentPlan ||
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
          0 => BeaconOverviewTab(
            state: state,
            onViewAllCommitments: () => _setTab(1),
            onEditTimelineUpdate: editUpdate,
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
                    overflowMenu: _beaconViewAppBarOverflow(
                      context: context,
                      state: state,
                      cubit: beaconViewCubit,
                      screenCubit: screenCubit,
                      l10n: l10n,
                    ),
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
                        ? () =>
                              unawaited(beaconViewCubit.moveToWatching())
                        : null,
                    onStopWatching:
                        !state.isBeaconMine &&
                            !state.isCommitted &&
                            state.inboxStatus == InboxItemStatus.watching
                        ? () => unawaited(beaconViewCubit.stopWatching())
                        : null,
                    onViewChain: () =>
                        screenCubit.showForwardsGraphFor(beaconId),
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
                            l10n.labelBeaconTabOverview,
                            l10n.labelBeaconTabPeople,
                            l10n.labelBeaconTabActivity,
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

  static const double _barHeight = 56;

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
    final beacon = state.beacon;
    final active = state.commitments
        .where((c) => !c.isWithdrawn)
        .toList(growable: false);
    final withdrawn = state.commitments
        .where((c) => c.isWithdrawn)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        BeaconEvaluationHooks(
          beaconId: beacon.id,
          lifecycle: beacon.lifecycle,
        ),
        if (active.isNotEmpty || withdrawn.isNotEmpty)
          const SizedBox(height: 12),
        for (var i = 0; i < active.length; i++) ...[
          if (i != 0) const SizedBox(height: 12),
          CommitmentTile(
            commitment: active[i],
            beaconId: beacon.id,
            beaconAuthorId: beacon.author.id,
            isMine: active[i].user.id == state.myProfile.id,
            isAuthorView: state.isBeaconMine,
            onAuthorTapCoordination:
                state.isBeaconMine && !active[i].isWithdrawn
                ? () => unawaited(
                    showCoordinationResponseBottomSheet(
                      context: context,
                      commitUserTitle: active[i].user.title,
                      initialResponse: active[i].coordinationResponse,
                      commitUserAdmittedToRoom: state.roomParticipants.any(
                        (p) =>
                            p.userId == active[i].user.id &&
                            p.roomAccess == RoomAccessBits.admitted,
                      ),
                      onSave:
                          ({
                            required responseTypeSmallint,
                            required inviteToRoom,
                            required removeFromRoom,
                          }) => beaconViewCubit.setCoordinationResponse(
                            commitUserId: active[i].user.id,
                            responseType: responseTypeSmallint,
                            inviteToRoom: inviteToRoom,
                            removeFromRoom: removeFromRoom,
                          ),
                    ),
                  )
                : null,
            onEdit:
                active[i].user.id == state.myProfile.id &&
                    !active[i].isWithdrawn
                ? () async {
                    final outcome = await CommitmentMessageDialog.show(
                      context,
                      title: l10n.beaconHeaderUpdateCommitment,
                      hintText: l10n.hintCommitMessage,
                      initialText: active[i].message,
                      allowEmptyMessage: true,
                      showHelpTypeChips: true,
                      initialHelpTypeSlugs: commitmentStoredHelpTypeSlugs(
                        active[i].helpType,
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
                active[i].user.id == state.myProfile.id &&
                    !active[i].isWithdrawn &&
                    beacon.allowsWithdrawWhileCommitted
                ? () async {
                    final outcome = await CommitmentMessageDialog.show(
                      context,
                      title: l10n.dialogWithdrawTitle,
                      hintText: l10n.hintWithdrawReason,
                      allowEmptyMessage: true,
                      requireUncommitReason: true,
                    );
                    if (outcome?.uncommitReasonWire != null &&
                        context.mounted) {
                      await beaconViewCubit.withdraw(
                        message: outcome!.message,
                        uncommitReason: outcome.uncommitReasonWire!,
                      );
                    }
                  }
                : null,
          ),
        ],
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
