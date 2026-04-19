import 'dart:async';

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_overflow_menu.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_evaluation_hooks.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';

import '../bloc/beacon_view_cubit.dart';
import '../dialog/commitment_message_dialog.dart';
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

/// Query [kQueryBeaconViewTab]: `timeline` | `commitments` | `details`.
int _beaconViewTabIndex(String? viewTab) {
  switch (viewTab) {
    case 'commitments':
      return 1;
    case 'details':
      return 2;
    case 'forwards':
      // Legacy tab id: forwards moved to [BeaconForwardsScreen].
      return 0;
    case 'timeline':
    default:
      return 0;
  }
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
    onCommit: !state.isCommitted && b.allowsNewCommitAsNonAuthor
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
    onWithdraw: state.isCommitted && b.allowsWithdrawWhileCommitted
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
    onForward: () => unawaited(
      context.router.pushPath('$kPathForwardBeacon/$beaconId'),
    ),
    onViewForwards: () => unawaited(
      context.router.pushPath('$kPathBeaconForwards/$beaconId'),
    ),
    onForwardsGraph: () => screenCubit.showForwardsGraphFor(beaconId),
    onWatch: state.inboxStatus == InboxItemStatus.needsMe
        ? () => unawaited(cubit.moveToWatching())
        : null,
    onStopWatching: state.inboxStatus == InboxItemStatus.watching
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

  /// `timeline` | `commitments` | `details` — initial tab in the detail tabs.
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
    final l10n = L10n.of(context)!;
    final screenCubit = context.read<ScreenCubit>();
    final beaconViewCubit = context.read<BeaconViewCubit>();
    return Scaffold(
      appBar: AppBar(
        title: BlocBuilder<BeaconViewCubit, BeaconViewState>(
          bloc: beaconViewCubit,
          buildWhen: (p, c) =>
              p.isLoading != c.isLoading ||
              p.beacon.author.id != c.beacon.author.id ||
              p.beacon.author.title != c.beacon.author.title,
          builder: (context, state) {
            if (state.isLoading) {
              return Text(l10n.beaconViewTitle);
            }
            final theme = Theme.of(context);
            final author = state.beacon.author;
            final name =
                author.title.isEmpty ? l10n.noName : author.title;
            return Row(
              children: [
                InkWell(
                  onTap: () =>
                      context.read<ScreenCubit>().showProfile(author.id),
                  customBorder: const CircleBorder(),
                  child: AvatarRated(
                    profile: author,
                    size: 32,
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: kPaddingH,
                    child: InkWell(
                      onTap: () => context
                          .read<ScreenCubit>()
                          .showProfile(author.id),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
        leading: isDeepLink == 'true'
            ? BackButton(
                onPressed: () => AutoRouter.of(context).navigatePath(kPathHome),
              )
            : const AutoLeadingButton(),
        actions: [
          BlocBuilder<BeaconViewCubit, BeaconViewState>(
            builder: (context, state) {
              return _beaconViewAppBarOverflow(
                context: context,
                state: state,
                cubit: beaconViewCubit,
                screenCubit: screenCubit,
                l10n: l10n,
              );
            },
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
          if (state.isLoading &&
              state.timeline.isEmpty &&
              state.commitments.isEmpty) {
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
                child: BeaconCardHeaderRow(
                  beacon: beacon,
                  titleMaxLines: 3,
                  subline: const SizedBox.shrink(),
                  menu: const SizedBox.shrink(),
                ),
              ),

              Padding(
                padding: kPaddingSmallV,
                child: Wrap(
                  spacing: kSpacingSmall,
                  runSpacing: kSpacingSmall,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    if (beacon.lifecycle != BeaconLifecycle.open)
                      BeaconCardPill(
                        label: _lifecycleLabel(l10n, beacon.lifecycle),
                      ),
                    if (state.isBeaconMine)
                      BeaconCardPill(
                        label: coordinationStatusLabel(
                          l10n,
                          beacon.coordinationStatus,
                        ),
                        backgroundColor: theme.colorScheme.surfaceContainerHigh,
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        onTap: () async {
                          await showBeaconCoordinationStatusBottomSheet(
                            context: context,
                            onPick: (s) => unawaited(
                              beaconViewCubit.setBeaconCoordinationStatus(
                                BeaconCoordinationStatus.fromSmallint(s),
                              ),
                            ),
                          );
                        },
                      )
                    else if (beacon.coordinationStatus !=
                            BeaconCoordinationStatus.noCommitmentsYet &&
                        beacon.coordinationStatus !=
                            BeaconCoordinationStatus
                                .commitmentsWaitingForReview)
                      BeaconCardPill(
                        label: coordinationStatusLabel(
                          l10n,
                          beacon.coordinationStatus,
                        ),
                        backgroundColor: theme.colorScheme.surfaceContainerHigh,
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                      ),
                  ],
                ),
              ),

              const SizedBox(height: kSpacingMedium),

              _TabSection(
                initialTabIndex: _beaconViewTabIndex(viewTab),
                beacon: beacon,
                timeline: state.timeline,
                commitments: state.commitments,
                myUserId: state.myProfile.id,
                isAuthorView: state.isBeaconMine,
                onPostUpdate: () async {
                  await _showPostAuthorUpdateSheet(
                    context,
                    beaconViewCubit,
                    l10n,
                  );
                },
                onEditTimelineUpdate: (u) async {
                  await _showEditAuthorUpdateSheet(
                    context,
                    beaconViewCubit,
                    l10n,
                    initial: u.content,
                    updateId: u.id,
                    createdAt: u.createdAt,
                  );
                },
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
    required this.beacon,
    required this.timeline,
    required this.commitments,
    required this.myUserId,
    required this.onEditCommitment,
    required this.isAuthorView,
    required this.onAuthorCoordination,
    required this.onPostUpdate,
    required this.onEditTimelineUpdate,
    this.initialTabIndex = 0,
  });

  final Beacon beacon;
  final int initialTabIndex;
  final List<TimelineEntry> timeline;
  final List<TimelineCommitment> commitments;
  final String myUserId;
  final Future<void> Function(TimelineCommitment) onEditCommitment;
  final bool isAuthorView;
  final Future<void> Function(TimelineCommitment) onAuthorCoordination;
  final Future<void> Function() onPostUpdate;
  final Future<void> Function(TimelineUpdate) onEditTimelineUpdate;

  @override
  State<_TabSection> createState() => _TabSectionState();
}

class _TabSectionState extends State<_TabSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  @override
  void initState() {
    super.initState();
    final idx = widget.initialTabIndex.clamp(0, 2);
    _tabController = TabController(
      length: 3,
      vsync: this,
      initialIndex: idx,
    );
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
    final beacon = widget.beacon;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.labelTimeline),
            Tab(text: l10n.labelCommitments),
            Tab(text: l10n.beaconDetailsSection),
          ],
        ),
        const SizedBox(height: kSpacingSmall),
        if (_tabController.index == 0) ...[
          if (widget.isAuthorView &&
              beacon.lifecycle == BeaconLifecycle.open)
            Padding(
              padding: const EdgeInsets.only(bottom: kSpacingSmall),
              child: FilledButton.icon(
                icon: const Icon(Icons.campaign_outlined),
                label: Text(l10n.postUpdateCTA),
                onPressed: () => unawaited(widget.onPostUpdate()),
              ),
            ),
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
            _TimelineEntryTile(
              entry: entry,
              beacon: beacon,
              isAuthorView: widget.isAuthorView,
              onEditTimelineUpdate: widget.onEditTimelineUpdate,
            ),
        ] else if (_tabController.index == 1) ...[
          BeaconEvaluationHooks(
            beaconId: beacon.id,
            lifecycle: beacon.lifecycle,
          ),
          Padding(
            padding: kPaddingSmallV,
            child: Wrap(
              spacing: kSpacingSmall,
              runSpacing: kSpacingSmall,
              children: [
                BeaconCardPill(
                  label: l10n.inboxCommitmentsCount(
                    widget.commitments.where((c) => !c.isWithdrawn).length,
                  ),
                ),
              ],
            ),
          ),
          for (final c in widget.commitments)
            CommitmentTile(
              commitment: c,
              beaconAuthor: beacon.author,
              isMine: c.user.id == widget.myUserId,
              isAuthorView: widget.isAuthorView,
              onAuthorTapCoordination: widget.isAuthorView && !c.isWithdrawn
                  ? () => unawaited(widget.onAuthorCoordination(c))
                  : null,
              onEdit: c.user.id == widget.myUserId && !c.isWithdrawn
                  ? () => unawaited(widget.onEditCommitment(c))
                  : null,
            ),
        ] else ...[
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              BeaconInfo(
                key: ValueKey(beacon),
                beacon: beacon,
                isTitleLarge: true,
                isShowMoreEnabled: false,
                isShowBeaconEnabled: false,
                showTitle: false,
              ),
              if (beacon.context.trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: kSpacingSmall),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Chip(
                      label: Text(beacon.context.trim()),
                    ),
                  ),
                ),
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
  final controller = TextEditingController();
  try {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
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
              Text(
                l10n.postUpdateCTA,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: kSpacingSmall),
              TextField(
                controller: controller,
                maxLines: 6,
                maxLength: kDescriptionMaxLength,
                decoration: InputDecoration(
                  hintText: l10n.beaconUpdateComposerHint,
                ),
              ),
              const SizedBox(height: kSpacingSmall),
              Text(
                l10n.beaconUpdateEditWindowHint,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: kSpacingSmall),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) return;
                  Navigator.of(ctx).pop(true);
                },
                child: Text(l10n.postUpdateCTA),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true) {
      final t = controller.text.trim();
      if (t.isNotEmpty) await cubit.postAuthorUpdate(t);
    }
  } finally {
    controller.dispose();
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
  final controller = TextEditingController(text: initial);
  try {
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
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
              Text(
                l10n.editUpdateCTA,
                style: Theme.of(ctx).textTheme.titleMedium,
              ),
              const SizedBox(height: kSpacingSmall),
              TextField(
                controller: controller,
                maxLines: 6,
                maxLength: kDescriptionMaxLength,
                decoration: InputDecoration(
                  hintText: l10n.beaconUpdateComposerHint,
                ),
              ),
              const SizedBox(height: kSpacingSmall),
              Text(
                l10n.beaconUpdateEditWindowHint,
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: kSpacingSmall),
              FilledButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) return;
                  Navigator.of(ctx).pop(true);
                },
                child: Text(l10n.buttonSaveChanges),
              ),
            ],
          ),
        );
      },
    );
    if (ok == true) {
      final t = controller.text.trim();
      if (t.isNotEmpty && t != initial) {
        await cubit.editAuthorUpdate(id: updateId, content: t);
      }
    }
  } finally {
    controller.dispose();
  }
}

String _timelineEventTimestamp(DateTime utc) {
  final local = utc.toLocal();
  return '${dateFormatYMD(local)} ${timeFormatHm(local)}';
}

String _timelineCommitmentUpdatedLine(L10n l10n, TimelineCommitmentUpdated e) {
  final base = l10n.timelineCommitmentDetailsUpdated(e.committer.title);
  final help = helpTypeLabel(l10n, e.helpType);
  if (help != null && help.isNotEmpty) {
    return '$base · $help';
  }
  return base;
}

class _TimelineEntryTile extends StatelessWidget {
  const _TimelineEntryTile({
    required this.entry,
    required this.beacon,
    required this.isAuthorView,
    required this.onEditTimelineUpdate,
  });

  final TimelineEntry entry;
  final Beacon beacon;
  final bool isAuthorView;
  final Future<void> Function(TimelineUpdate u) onEditTimelineUpdate;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: kPaddingSmallV,
      child: switch (entry) {
        final TimelineCommitmentCreated e => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.handshake,
              size: 18,
              color: theme.colorScheme.tertiary,
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              child: Text(
                e.message.isNotEmpty
                    ? l10n.timelineCommittedWithMessage(
                        e.committer.title,
                        e.message,
                      )
                    : l10n.timelineCommitted(e.committer.title),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              _timelineEventTimestamp(e.timestamp),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        final TimelineCommitmentUpdated e => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.edit_note,
              size: 18,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              child: Text(
                _timelineCommitmentUpdatedLine(l10n, e),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              _timelineEventTimestamp(e.timestamp),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        final TimelineAuthorCoordinationResponse e => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.flag_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              child: Text(
                l10n.timelineAuthorCoordinationResponseLine(
                  e.author.title,
                  e.committer.title,
                  coordinationResponseLabel(l10n, e.response) ?? '',
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              _timelineEventTimestamp(e.timestamp),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        final TimelineCommitmentWithdrawn e => Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.heart_broken,
              size: 18,
              color: theme.colorScheme.error,
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              child: Text(
                e.message.isNotEmpty
                    ? l10n.timelineWithdrewWithMessage(
                        e.committer.title,
                        e.message,
                      )
                    : l10n.timelineWithdrew(e.committer.title),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.edit_note,
              size: 18,
              color: theme.colorScheme.secondary,
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              child: Text(
                '${l10n.updateNumberLabel(e.number)} · ${l10n.timelineUpdate(e.author.title, e.content)}',
                style: theme.textTheme.bodySmall,
              ),
            ),
            if (isAuthorView &&
                beacon.lifecycle == BeaconLifecycle.open &&
                _authorUpdateEditableNow(e.createdAt))
              IconButton(
                tooltip: l10n.editUpdateCTA,
                icon: const Icon(Icons.edit_outlined),
                iconSize: 18,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                onPressed: () => unawaited(onEditTimelineUpdate(e)),
              ),
            Text(
              _timelineEventTimestamp(e.timestamp),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        final TimelineBeaconCoordinationStatusChanged e => Row(
          children: [
            Icon(
              Icons.sync_alt,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              child: Text(
                l10n.timelineBeaconCoordinationStatusChanged(
                  e.author.title,
                  coordinationStatusLabel(l10n, e.status),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              _timelineEventTimestamp(e.timestamp),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        final TimelineBeaconLifecycleChanged e => Row(
          children: [
            Icon(
              Icons.flag_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              child: Text(
                l10n.timelineBeaconLifecycleChanged(
                  e.author.title,
                  _lifecycleLabel(l10n, e.lifecycle),
                ),
                style: theme.textTheme.bodySmall,
              ),
            ),
            Text(
              _timelineEventTimestamp(e.timestamp),
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
        final TimelineCreation e => Row(
          children: [
            Icon(
              Icons.flag_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              child: Text(
                l10n.timelineCreated(e.author.title),
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
