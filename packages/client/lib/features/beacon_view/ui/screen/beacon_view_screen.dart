import 'dart:async';

import 'package:nil/nil.dart';
import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/ui/widget/author_info.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_evaluation_hooks.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';

import '../bloc/beacon_view_cubit.dart';
import '../dialog/commitment_message_dialog.dart';
import '../widget/beacon_mine_control.dart';
import '../widget/commitment_tile.dart';
import '../widget/coordination_response_bottom_sheet.dart';

String _lifecycleLabel(L10n l10n, BeaconLifecycle lc) => switch (lc) {
      BeaconLifecycle.open => l10n.beaconLifecycleOpen,
      BeaconLifecycle.closed => l10n.beaconLifecycleClosed,
      BeaconLifecycle.deleted => l10n.beaconLifecycleDeleted,
      BeaconLifecycle.draft => l10n.beaconLifecycleDraft,
      BeaconLifecycle.pendingReview => l10n.beaconLifecyclePendingReview,
      BeaconLifecycle.closedReviewOpen => l10n.beaconLifecycleClosedReviewOpen,
      BeaconLifecycle.closedReviewComplete =>
        l10n.beaconLifecycleClosedReviewComplete,
    };

@RoutePage()
class BeaconViewScreen extends StatelessWidget implements AutoRouteWrapper {
  const BeaconViewScreen({
    @PathParam('id') this.id = '',
    @QueryParam(kQueryIsDeepLink) this.isDeepLink,
    super.key,
  });

  final String id;

  final String? isDeepLink;

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
    final l10n = L10n.of(context)!;
    final screenCubit = context.read<ScreenCubit>();
    final beaconViewCubit = context.read<BeaconViewCubit>();
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.beaconViewTitle),
        leading: isDeepLink == 'true'
            ? BackButton(
                onPressed: () => AutoRouter.of(context).navigatePath(kPathHome),
              )
            : const AutoLeadingButton(),
        actions: [
          BlocSelector<BeaconViewCubit, BeaconViewState, bool>(
            selector: (state) => state.isBeaconMine,
            builder: (_, isBeaconMine) => isBeaconMine
                ? nil
                : PopupMenuButton(
                    itemBuilder: (_) => <PopupMenuEntry<void>>[
                      PopupMenuItem(
                        onTap: () => screenCubit.showComplaint(id),
                        child: Text(l10n.buttonComplaint),
                      ),
                    ],
                  ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: BlocSelector<BeaconViewCubit, BeaconViewState, bool>(
            selector: (state) => state.isLoading,
            builder: LinearPiActive.builder,
            bloc: beaconViewCubit,
          ),
        ),
      ),
      body: BlocBuilder<BeaconViewCubit, BeaconViewState>(
        bloc: beaconViewCubit,
        buildWhen: (_, c) => c.isSuccess || c.isLoading || c.hasError,
        builder: (_, state) {
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }
          final beacon = state.beacon;
          final theme = Theme.of(context);
          return ListView(
            padding: kPaddingAll,
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: kSpacingSmall),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    BeaconIdentityTile(beacon: beacon, size: 64),
                    const SizedBox(width: kSpacingSmall),
                    Expanded(
                      child: Text(
                        beacon.title,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineLarge,
                      ),
                    ),
                  ],
                ),
              ),

              // Author (beacon owner; not the forwarder)
              if (state.isBeaconNotMine)
                AuthorInfo(
                  author: beacon.author,
                  key: ValueKey(beacon.author),
                ),

              // Beacon Info (overview): gallery + description; title shown above
              BeaconInfo(
                key: ValueKey(beacon),
                beacon: beacon,
                isTitleLarge: true,
                isShowMoreEnabled: false,
                isShowBeaconEnabled: false,
                showTitle: false,
              ),

              Padding(
                padding: kPaddingSmallV,
                child: Wrap(
                  spacing: kSpacingSmall,
                  runSpacing: kSpacingSmall,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Chip(
                      label: Text(_lifecycleLabel(l10n, beacon.lifecycle)),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    Chip(
                      label: Text(
                        coordinationStatusLabel(l10n, beacon.coordinationStatus),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    Chip(
                      label: Text(
                        l10n.labelCommitmentCount(
                          state.commitments
                              .where((c) => !c.isWithdrawn)
                              .length,
                        ),
                      ),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    if (state.isBeaconMine)
                      TextButton(
                        onPressed: () async {
                          await showBeaconCoordinationStatusBottomSheet(
                            context: context,
                            onPick: (s) => unawaited(
                              beaconViewCubit.setBeaconCoordinationStatus(
                                BeaconCoordinationStatus.fromSmallint(s),
                              ),
                            ),
                          );
                        },
                        child: Text(l10n.coordinationSetOverallStatus),
                      ),
                  ],
                ),
              ),

              BeaconEvaluationHooks(
                beaconId: beacon.id,
                lifecycle: beacon.lifecycle,
              ),

              // Beacon owner controls
              if (state.isBeaconMine)
                Padding(
                  padding: kPaddingSmallV,
                  child: BeaconMineControl(key: ValueKey(beacon.id)),
                ),

              const SizedBox(height: kSpacingMedium),

              // Primary actions for non-owners
              if (state.isBeaconNotMine)
                Padding(
                  padding: kPaddingSmallV,
                  child: Row(
                    children: [
                      Expanded(
                        child: BlocSelector<BeaconViewCubit, BeaconViewState,
                            ({bool isCommitted, Beacon beacon})>(
                          selector: (s) =>
                              (isCommitted: s.isCommitted, beacon: s.beacon),
                          builder: (_, row) {
                            final useCommitAnyway = row.beacon
                                    .coordinationStatus ==
                                BeaconCoordinationStatus.enoughHelpCommitted;
                            return row.isCommitted
                                ? OutlinedButton.icon(
                                    onPressed: row.beacon
                                            .allowsWithdrawWhileCommitted
                                        ? () async {
                                            final outcome =
                                                await CommitmentMessageDialog
                                                    .show(
                                              context,
                                              title: l10n.dialogWithdrawTitle,
                                              hintText: l10n.hintWithdrawReason,
                                              allowEmptyMessage: true,
                                              requireUncommitReason: true,
                                            );
                                            if (outcome?.uncommitReasonWire !=
                                                null) {
                                              await beaconViewCubit.withdraw(
                                                message: outcome!.message,
                                                uncommitReason: outcome
                                                    .uncommitReasonWire!,
                                              );
                                            }
                                          }
                                        : null,
                                    icon: const Icon(Icons.check_circle),
                                    label: Text(l10n.labelCommitted),
                                  )
                                : FilledButton.icon(
                                    onPressed: row.beacon
                                            .allowsNewCommitAsNonAuthor
                                        ? () async {
                                            final outcome =
                                                await CommitmentMessageDialog
                                                    .show(
                                              context,
                                              title: useCommitAnyway
                                                  ? l10n.dialogCommitAnywayTitle
                                                  : l10n.dialogCommitTitle,
                                              hintText: l10n.hintCommitMessage,
                                              allowEmptyMessage: true,
                                              showHelpTypeChips: true,
                                            );
                                            if (outcome != null) {
                                              await beaconViewCubit.commit(
                                                message: outcome.message,
                                                helpType: outcome.helpTypeWire,
                                              );
                                            }
                                          }
                                        : null,
                                    icon: const Icon(Icons.handshake),
                                    label: Text(
                                      useCommitAnyway
                                          ? l10n.labelCommitAnyway
                                          : l10n.labelCommit,
                                    ),
                                  );
                          },
                        ),
                      ),
                      const SizedBox(width: kSpacingSmall),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => context.router.pushPath(
                            '$kPathForwardBeacon/${beacon.id}',
                          ),
                          icon: const Icon(Icons.send),
                          label: Text(l10n.labelForward),
                        ),
                      ),
                    ],
                  ),
                ),

              if (state.isBeaconNotMine &&
                  state.inboxStatus == InboxItemStatus.needsMe)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: () =>
                        unawaited(beaconViewCubit.moveToWatching()),
                    icon: Icon(
                      Icons.visibility_outlined,
                      size: 20,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    label: Text(l10n.actionWatch),
                    style: TextButton.styleFrom(
                      foregroundColor:
                          Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),

              // Forward button for owners (hidden once they have forwarded; overflow still has Forward)
              if (state.isBeaconMine && !state.hasForwardedThisBeaconOnce)
                Padding(
                  padding: kPaddingSmallV,
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => context.router.pushPath(
                        '$kPathForwardBeacon/${beacon.id}',
                      ),
                      icon: const Icon(Icons.send),
                      label: Text(l10n.labelForward),
                    ),
                  ),
                ),

              const Divider(height: kSpacingLarge),

              _TabSection(
                timeline: state.timeline,
                commitments: state.commitments,
                myUserId: state.myProfile.id,
                isAuthorView: state.isBeaconMine,
                onEditCommitment: (commitment) async {
                  final outcome = await CommitmentMessageDialog.show(
                    context,
                    title: l10n.dialogUpdateCommitTitle,
                    hintText: l10n.hintCommitMessage,
                    initialText: commitment.message,
                  );
                  if (outcome != null && outcome.message.isNotEmpty) {
                    await beaconViewCubit.commit(message: outcome.message);
                  }
                },
                onAuthorCoordination: (commitment) async {
                  await showCoordinationResponseBottomSheet(
                    context: context,
                    commitUserTitle: commitment.user.title,
                    onPick: (t) => unawaited(
                      beaconViewCubit.setCoordinationResponse(
                        commitUserId: commitment.user.id,
                        responseType: t,
                      ),
                    ),
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TabSection extends StatefulWidget {
  const _TabSection({
    required this.timeline,
    required this.commitments,
    required this.myUserId,
    required this.onEditCommitment,
    required this.isAuthorView,
    required this.onAuthorCoordination,
  });

  final List<TimelineEntry> timeline;
  final List<TimelineCommitment> commitments;
  final String myUserId;
  final Future<void> Function(TimelineCommitment) onEditCommitment;
  final bool isAuthorView;
  final Future<void> Function(TimelineCommitment) onAuthorCoordination;

  @override
  State<_TabSection> createState() => _TabSectionState();
}

class _TabSectionState extends State<_TabSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  @override
  void initState() {
    super.initState();
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.labelTimeline),
            Tab(text: l10n.labelCommitments),
          ],
        ),
        const SizedBox(height: kSpacingSmall),
        if (_tabController.index == 0) ...[
          if (widget.timeline.isEmpty)
            Padding(
              padding: kPaddingSmallV,
              child: Text(
                l10n.noActivityYet,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final entry in widget.timeline)
            _TimelineEntryTile(entry: entry),
        ] else ...[
          if (widget.commitments.isEmpty)
            Padding(
              padding: kPaddingSmallV,
              child: Text(
                l10n.noCommitmentsYet,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          for (final c in widget.commitments)
            CommitmentTile(
              commitment: c,
              isMine: c.user.id == widget.myUserId,
              isAuthorView: widget.isAuthorView,
              onAuthorTapCoordination: widget.isAuthorView && !c.isWithdrawn
                  ? () => unawaited(widget.onAuthorCoordination(c))
                  : null,
              onEdit: c.user.id == widget.myUserId && !c.isWithdrawn
                  ? () => unawaited(widget.onEditCommitment(c))
                  : null,
            ),
        ],
      ],
    );
  }
}

String _timelineEventTimestamp(DateTime utc) {
  final local = utc.toLocal();
  return '${dateFormatYMD(local)} ${timeFormatHm(local)}';
}

class _TimelineEntryTile extends StatelessWidget {
  const _TimelineEntryTile({required this.entry});

  final TimelineEntry entry;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: kPaddingSmallV,
      child: switch (entry) {
        final TimelineCommitment e => Row(
            children: [
              Icon(
                e.isWithdrawn ? Icons.heart_broken : Icons.handshake,
                size: 18,
                color: e.isWithdrawn
                    ? theme.colorScheme.error
                    : theme.colorScheme.tertiary,
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  e.isWithdrawn
                      ? (e.message.isNotEmpty
                          ? l10n.timelineWithdrewWithMessage(
                              e.user.title,
                              e.message,
                            )
                          : l10n.timelineWithdrew(e.user.title))
                      : (e.message.isNotEmpty
                          ? l10n.timelineCommittedWithMessage(
                              e.user.title,
                              e.message,
                            )
                          : l10n.timelineCommitted(e.user.title)),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                _timelineEventTimestamp(e.timestamp),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
        final TimelineUpdate e => Row(
            children: [
              Icon(
                Icons.edit_note,
                size: 18,
                color: theme.colorScheme.secondary,
              ),
              const SizedBox(width: kSpacingSmall),
              Expanded(
                child: Text(
                  l10n.timelineUpdate(e.author.title, e.content),
                  style: theme.textTheme.bodySmall,
                ),
              ),
              Text(
                _timelineEventTimestamp(e.timestamp),
                style: theme.textTheme.labelSmall,
              ),
            ],
          ),
      },
    );
  }
}
