import 'dart:async';

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/auto_leading_with_fallback.dart';
import 'package:tentura/ui/widget/inbox_style_app_bar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_evaluation_hooks.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';

import 'package:tentura/domain/entity/beacon_people_lens.dart';

import '../bloc/beacon_view_cubit.dart';
import '../dialog/commitment_message_dialog.dart';
import '../widget/activity_list.dart';
import '../widget/beacon_operational_header_card.dart';
import '../widget/commitment_tile.dart';
import '../widget/commitments_summary_card.dart';
import '../widget/coordination_response_bottom_sheet.dart';
import '../widget/beacon_people_participant_card.dart';
import '../widget/overview/beacon_overview_tab.dart';

/// Query [kQueryBeaconViewTab]: `overview` | `commitments` | `activity` (legacy: `timeline`, `details`, `forwards`).
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
        context.router.pushPath('$kPathForwardBeacon/$beaconId'),
      ),
      onViewForwards: () => unawaited(
        context.router.pushPath('$kPathBeaconForwards/$beaconId'),
      ),
      onForwardsGraph: () => screenCubit.showForwardsGraphFor(beaconId),
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
            if (!context.mounted) return;
            final useCommitAnyway =
                state.beacon.coordinationStatus ==
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
                helpType: outcome.helpTypeWire,
              );
            }
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
            context.router.pushPath('$kPathForwardBeacon/$beaconId'),
          ),
    onViewForwards: () => unawaited(
      context.router.pushPath('$kPathBeaconForwards/$beaconId'),
    ),
    onForwardsGraph: () => screenCubit.showForwardsGraphFor(beaconId),
    onWatch: !state.isCommitted &&
        state.inboxStatus == InboxItemStatus.needsMe
        ? () => unawaited(cubit.moveToWatching())
        : null,
    onStopWatching: !state.isCommitted &&
        state.inboxStatus == InboxItemStatus.watching
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
class BeaconViewScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconViewScreen({
    @PathParam('id') this.id = '',
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    @QueryParam(kQueryBeaconViewTab) this.viewTab,
    super.key,
  });

  final String id;

  final String? isDeepLink;

  /// `overview` | `commitments` | `activity` (legacy: `timeline`, `details`, `forwards`).
  final String? viewTab;

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
  Widget build(BuildContext context) {
    final screenCubit = context.read<ScreenCubit>();
    final beaconViewCubit = context.read<BeaconViewCubit>();
    final l10n = L10n.of(context)!;
    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      bloc: beaconViewCubit,
      buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
      builder: (context, state) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        final showInitialLoading =
            state.isLoading &&
            state.timeline.isEmpty &&
            state.commitments.isEmpty;
        return Scaffold(
          appBar: AppBar(
            backgroundColor: scheme.surface,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            toolbarHeight: InboxStyleAppBar.toolbarHeight,
            leadingWidth: InboxStyleAppBar.toolbarHeight,
            foregroundColor: scheme.onSurface,
            titleTextStyle: theme.textTheme.titleLarge!.copyWith(
              color: scheme.onSurface,
            ),
            titleSpacing: 8,
            leading: const AutoLeadingWithFallback(fallbackPath: kPathHome),
            title: Text(l10n.beaconViewTitle),
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
          body: showInitialLoading
              ? const Center(
                  child: CircularProgressIndicator.adaptive(),
                )
              : _BeaconOperationalScrollView(
                  beaconViewCubit: beaconViewCubit,
                  screenCubit: screenCubit,
                  initialTabIndex: _beaconViewTabIndex(viewTab),
                ),
        );
      },
    );
  }
}

class _BeaconOperationalScrollView extends StatefulWidget {
  const _BeaconOperationalScrollView({
    required this.beaconViewCubit,
    required this.screenCubit,
    required this.initialTabIndex,
  });

  final BeaconViewCubit beaconViewCubit;
  final ScreenCubit screenCubit;
  final int initialTabIndex;

  @override
  State<_BeaconOperationalScrollView> createState() =>
      _BeaconOperationalScrollViewState();
}

class _BeaconOperationalScrollViewState
    extends State<_BeaconOperationalScrollView> {
  late int _tabIndex;

  @override
  void initState() {
    super.initState();
    _tabIndex = widget.initialTabIndex.clamp(0, 2);
  }

  void _setTab(int i) {
    if (_tabIndex == i) return;
    setState(() {
      _tabIndex = i;
    });
  }

  Future<void> _pickCoordinationStatus(BuildContext context) async {
    await showBeaconCoordinationStatusBottomSheet(
      context: context,
      onPick: (s) => unawaited(
        widget.beaconViewCubit.setBeaconCoordinationStatus(
          BeaconCoordinationStatus.fromSmallint(s),
        ),
      ),
    );
  }

  Future<void> _runCommitFlow(BuildContext context, L10n l10n) async {
    if (!context.mounted) return;
    final useCommitAnyway =
        widget.beaconViewCubit.state.beacon.coordinationStatus ==
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
      await widget.beaconViewCubit.commit(
        message: outcome.message,
        helpType: outcome.helpTypeWire,
      );
    }
  }

  Future<void> _runUpdateCommitFlow(BuildContext context, L10n l10n) async {
    if (!context.mounted) return;
    final cubit = widget.beaconViewCubit;
    var initialMessage = '';
    for (final c in cubit.state.commitments) {
      if (!c.isWithdrawn && c.user.id == cubit.state.myProfile.id) {
        initialMessage = c.message;
        break;
      }
    }
    final outcome = await CommitmentMessageDialog.show(
      context,
      title: l10n.beaconHeaderUpdateCommitment,
      hintText: l10n.hintCommitMessage,
      initialText: initialMessage,
      allowEmptyMessage: true,
      showHelpTypeChips: true,
    );
    if (outcome != null && context.mounted) {
      await cubit.commit(
        message: outcome.message,
        helpType: outcome.helpTypeWire,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<BeaconViewCubit, BeaconViewState>(
      bloc: widget.beaconViewCubit,
      buildWhen: (p, c) =>
          p.beacon != c.beacon ||
          p.beacon.coordinationStatus != c.beacon.coordinationStatus ||
          p.beacon.lifecycle != c.beacon.lifecycle ||
          p.timeline != c.timeline ||
          p.commitments != c.commitments ||
          p.isCommitted != c.isCommitted ||
          p.isLoading != c.isLoading ||
          p.forwardProvenance != c.forwardProvenance ||
          p.inboxStatus != c.inboxStatus ||
          p.viewerForwardEdges != c.viewerForwardEdges ||
          p.factCards != c.factCards ||
          p.roomParticipants.length != c.roomParticipants.length ||
          (p.roomParticipants.map((e) => '${e.userId}|${e.userTitle}|${e.nextMoveText}').join() !=
              c.roomParticipants.map((e) => '${e.userId}|${e.userTitle}|${e.nextMoveText}').join()) ||
          p.beaconRoomCue?.lastRoomMeaningfulChange !=
              c.beaconRoomCue?.lastRoomMeaningfulChange ||
          p.beaconRoomCue?.currentPlan != c.beaconRoomCue?.currentPlan,
      builder: (context, state) {
        final beaconId = state.beacon.id;
        Future<void> editUpdate(TimelineUpdate u) => _showEditAuthorUpdateSheet(
          context,
          widget.beaconViewCubit,
          l10n,
          initial: u.content,
          updateId: u.id,
          createdAt: u.createdAt,
        );

        final tabBody = switch (_tabIndex) {
          0 => BeaconOverviewTab(
            state: state,
            onViewAllCommitments: () => _setTab(1),
            onEditTimelineUpdate: editUpdate,
          ),
          1 => _CommitmentsTabBody(
            state: state,
            beaconViewCubit: widget.beaconViewCubit,
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

        final tabPadding = _tabIndex == 0
            ? const EdgeInsets.fromLTRB(
                kSpacingMedium,
                kSpacingSmall / 2,
                kSpacingMedium,
                kSpacingSmall,
              )
            : _tabIndex == 1
            ? const EdgeInsets.fromLTRB(16, 12, 16, 12)
            : kPaddingAll;

        // Single CustomScrollView (no NestedScrollView) so the scroll position
        // is unified: there is no outer/inner coordinator that can let the
        // body scroll past its end when the tab content fits the viewport.
        return CustomScrollView(
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
                    cubit: widget.beaconViewCubit,
                    screenCubit: widget.screenCubit,
                    l10n: l10n,
                  ),
                  onAuthorTap: () =>
                      widget.screenCubit.showProfile(state.beacon.author.id),
                  onUpdateStatus: state.isBeaconMine &&
                          state.beacon.lifecycle == BeaconLifecycle.open
                      ? () => unawaited(_pickCoordinationStatus(context))
                      : null,
                  onPostUpdate: state.isBeaconMine &&
                          state.beacon.lifecycle == BeaconLifecycle.open
                      ? () => unawaited(
                            _showPostAuthorUpdateSheet(
                              context,
                              widget.beaconViewCubit,
                              l10n,
                            ),
                          )
                      : null,
                  onCommit: !state.isBeaconMine &&
                          state.beacon.lifecycle == BeaconLifecycle.open &&
                          !state.isCommitted &&
                          state.beacon.allowsNewCommitAsNonAuthor
                      ? () => _runCommitFlow(context, l10n)
                      : null,
                  onUpdateCommitment: !state.isBeaconMine &&
                          state.beacon.lifecycle == BeaconLifecycle.open &&
                          state.isCommitted &&
                          state.beacon.allowsWithdrawWhileCommitted
                      ? () => unawaited(_runUpdateCommitFlow(context, l10n))
                      : null,
                  onForward: () => unawaited(
                        context.router.pushPath('$kPathForwardBeacon/$beaconId'),
                      ),
                  onWatch: !state.isBeaconMine &&
                      !state.isCommitted &&
                      state.inboxStatus == InboxItemStatus.needsMe
                      ? () => unawaited(widget.beaconViewCubit.moveToWatching())
                      : null,
                  onStopWatching: !state.isBeaconMine &&
                      !state.isCommitted &&
                      state.inboxStatus == InboxItemStatus.watching
                      ? () =>
                            unawaited(widget.beaconViewCubit.stopWatching())
                      : null,
                  onRoom: state.canNavigateBeaconRoom
                      ? () => unawaited(
                            context.router
                                .pushPath('$kPathBeaconRoom/$beaconId'),
                          )
                      : null,
                  onViewChain: () =>
                      widget.screenCubit.showForwardsGraphFor(beaconId),
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
                        selectedIndex: _tabIndex,
                        onChanged: _setTab,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SliverPadding(
              key: ValueKey<int>(_tabIndex),
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
    final usefulCount = active
        .where((c) => c.coordinationResponse == CoordinationResponseType.useful)
        .length;
    final needsCoordinationCount = active
        .where(
          (c) =>
              c.coordinationResponse ==
              CoordinationResponseType.needCoordination,
        )
        .length;

    final peopleRows = beaconParticipantsVisibleForViewer(
      participants: state.roomParticipants,
      viewerUserId: state.myProfile.id,
      authorUserId: beacon.author.id,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (peopleRows.isNotEmpty) ...[
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              l10n.beaconPeopleSectionTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < peopleRows.length; i++) ...[
            if (i != 0) const SizedBox(height: 12),
            BeaconPeopleParticipantCard(
              beacon: beacon,
              participant: peopleRows[i],
              commitments: state.commitments,
            ),
          ],
          const SizedBox(height: 16),
        ],
        BeaconEvaluationHooks(
          beaconId: beacon.id,
          lifecycle: beacon.lifecycle,
        ),
        CommitmentsSummaryCard(
          activeCount: active.length,
          usefulCount: usefulCount,
          needsCoordinationCount: needsCoordinationCount,
        ),
        if (active.isNotEmpty || withdrawn.isNotEmpty)
          const SizedBox(height: 12),
        for (var i = 0; i < active.length; i++) ...[
          if (i != 0) const SizedBox(height: 12),
          CommitmentTile(
            commitment: active[i],
            isMine: active[i].user.id == state.myProfile.id,
            isAuthorView: state.isBeaconMine,
            onAuthorTapCoordination: state.isBeaconMine && !active[i].isWithdrawn
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
                      onSave: ({
                        required responseTypeSmallint,
                        required inviteToRoom,
                        required removeFromRoom,
                      }) =>
                          beaconViewCubit.setCoordinationResponse(
                            commitUserId: active[i].user.id,
                            responseType: responseTypeSmallint,
                            inviteToRoom: inviteToRoom,
                            removeFromRoom: removeFromRoom,
                          ),
                    ),
                  )
                : null,
            onEdit: active[i].user.id == state.myProfile.id && !active[i].isWithdrawn
                ? () async {
                    final outcome = await CommitmentMessageDialog.show(
                      context,
                      title: l10n.dialogUpdateCommitTitle,
                      hintText: l10n.hintCommitMessage,
                      initialText: active[i].message,
                    );
                    if (outcome != null &&
                        outcome.message.isNotEmpty &&
                        context.mounted) {
                      await beaconViewCubit.commit(message: outcome.message);
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

class _AuthorUpdateComposerSheetState extends State<_AuthorUpdateComposerSheet> {
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
