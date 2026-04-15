import 'dart:async';

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/beacon_identity_tile.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';
import 'package:tentura/ui/widget/author_info.dart';

import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_evaluation_hooks.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/inbox_forward_provenance_panel.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/tentura_icons.dart';

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

/// Query [kQueryBeaconViewTab]: `timeline` | `commitments` | `forwards`.
int _beaconViewTabIndex(String? viewTab) {
  switch (viewTab) {
    case 'commitments':
      return 1;
    case 'forwards':
      return 2;
    case 'timeline':
    default:
      return 0;
  }
}

Widget _beaconOverflowMenuRow(IconData icon, String label) {
  return Row(
    children: [
      Icon(icon, size: 22),
      const SizedBox(width: 12),
      Expanded(child: Text(label)),
    ],
  );
}

List<PopupMenuEntry<String>> _beaconOverflowItems(
  BeaconViewState state,
  L10n l10n,
) {
  final b = state.beacon;
  final items = <PopupMenuEntry<String>>[];

  if (state.isBeaconMine) {
    if (b.myVote >= 0) {
      items.add(
        PopupMenuItem(
          value: 'graph',
          child: _beaconOverflowMenuRow(TenturaIcons.graph, l10n.graphView),
        ),
      );
    }
    items
      ..add(
        PopupMenuItem(
          value: 'share',
          child: _beaconOverflowMenuRow(Icons.qr_code, l10n.shareLink),
        ),
      )
      ..add(
        PopupMenuItem(
          value: 'toggle_lifecycle',
          child: _beaconOverflowMenuRow(
            b.isListed ? Icons.lock_outline : Icons.lock_open,
            b.isListed ? l10n.closeBeacon : l10n.openBeacon,
          ),
        ),
      )
      ..add(
        PopupMenuItem(
          value: 'forward',
          child: _beaconOverflowMenuRow(Icons.send, l10n.labelForward),
        ),
      )
      ..add(
        PopupMenuItem(
          value: 'delete',
          child:
              _beaconOverflowMenuRow(Icons.delete_outline, l10n.deleteBeacon),
        ),
      );
    return items;
  }

  if (!state.isCommitted && b.allowsNewCommitAsNonAuthor) {
    final useCommitAnyway =
        b.coordinationStatus == BeaconCoordinationStatus.enoughHelpCommitted;
    items.add(
      PopupMenuItem(
        value: 'commit',
        child: _beaconOverflowMenuRow(
          Icons.handshake,
          useCommitAnyway ? l10n.labelCommitAnyway : l10n.labelCommit,
        ),
      ),
    );
  }
  if (state.isCommitted && b.allowsWithdrawWhileCommitted) {
    items.add(
      PopupMenuItem(
        value: 'withdraw',
        child: _beaconOverflowMenuRow(
          Icons.remove_circle_outline,
          l10n.dialogWithdrawTitle,
        ),
      ),
    );
  }
  items.add(
    PopupMenuItem(
      value: 'forward',
      child: _beaconOverflowMenuRow(Icons.send, l10n.labelForward),
    ),
  );
  if (state.inboxStatus == InboxItemStatus.needsMe) {
    items.add(
      PopupMenuItem(
        value: 'watch',
        child: _beaconOverflowMenuRow(
          Icons.visibility_outlined,
          l10n.actionWatch,
        ),
      ),
    );
  }
  if (state.inboxStatus == InboxItemStatus.watching) {
    items.add(
      PopupMenuItem(
        value: 'stop_watch',
        child: _beaconOverflowMenuRow(
          Icons.visibility_off_outlined,
          l10n.actionStopWatching,
        ),
      ),
    );
  }
  if (state.inboxStatus == InboxItemStatus.needsMe ||
      state.inboxStatus == InboxItemStatus.watching) {
    items.add(
      PopupMenuItem(
        value: 'cant_help',
        child: _beaconOverflowMenuRow(Icons.close, l10n.actionCantHelp),
      ),
    );
  }
  if (state.inboxStatus == InboxItemStatus.rejected) {
    items.add(
      PopupMenuItem(
        value: 'move_inbox',
        child: _beaconOverflowMenuRow(
          Icons.inbox_outlined,
          l10n.actionMoveToInbox,
        ),
      ),
    );
  }
  items.add(
    PopupMenuItem(
      value: 'complaint',
      child: _beaconOverflowMenuRow(Icons.flag_outlined, l10n.buttonComplaint),
    ),
  );
  return items;
}

Future<void> _onBeaconOverflowSelected(
  BuildContext context,
  String value,
  BeaconViewCubit cubit,
  ScreenCubit screenCubit,
  BeaconViewState state,
) async {
  final l10n = L10n.of(context)!;
  final beaconId = state.beacon.id;
  switch (value) {
    case 'graph':
      if (!state.isBeaconMine || state.beacon.myVote < 0) return;
      screenCubit.showGraphFor(beaconId);
      return;
    case 'share':
      if (!state.isBeaconMine) return;
      await ShareCodeDialog.show(
        context,
        link: Uri.parse(kServerName).replace(
          queryParameters: {'id': beaconId},
          path: kPathAppLinkView,
        ),
        header: beaconId,
      );
      return;
    case 'toggle_lifecycle':
      if (!state.isBeaconMine) return;
      if (state.beacon.isListed) {
        if (await BeaconCloseConfirmDialog.show(context) != true) {
          return;
        }
        if (!context.mounted) return;
      }
      await cubit.toggleLifecycle();
      return;
    case 'delete':
      if (!state.isBeaconMine) return;
      if (await BeaconDeleteDialog.show(context) ?? false) {
        if (!context.mounted) return;
        await cubit.delete(beaconId);
      }
      return;
    case 'commit':
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
      return;
    case 'withdraw':
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
      return;
    case 'forward':
      if (context.mounted) {
        await context.router.pushPath('$kPathForwardBeacon/$beaconId');
      }
      return;
    case 'watch':
      await cubit.moveToWatching();
      return;
    case 'stop_watch':
      await cubit.stopWatching();
      return;
    case 'cant_help':
      final msg = await showRejectionDialog(context);
      if (context.mounted && msg != null) {
        await cubit.rejectInbox(message: msg);
      }
      return;
    case 'move_inbox':
      await cubit.unrejectInbox();
      return;
    case 'complaint':
      screenCubit.showComplaint(beaconId);
      return;
    default:
      return;
  }
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

  /// `timeline` | `commitments` | `forwards` — initial tab in the detail tabs.
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
        title: Text(l10n.beaconViewTitle),
        leading: isDeepLink == 'true'
            ? BackButton(
                onPressed: () => AutoRouter.of(context).navigatePath(kPathHome),
              )
            : const AutoLeadingButton(),
        actions: [
          BlocBuilder<BeaconViewCubit, BeaconViewState>(
            builder: (context, state) {
              final entries = _beaconOverflowItems(state, l10n);
              if (entries.isEmpty) return const SizedBox.shrink();
              return PopupMenuButton<String>(
                onSelected: (v) => unawaited(
                  _onBeaconOverflowSelected(
                    context,
                    v,
                    beaconViewCubit,
                    screenCubit,
                    state,
                  ),
                ),
                itemBuilder: (_) => entries,
                child: const Icon(Icons.more_vert),
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
                    if (beacon.lifecycle != BeaconLifecycle.open)
                      BeaconCardPill(
                        label: _lifecycleLabel(l10n, beacon.lifecycle),
                      ),
                    if (beacon.coordinationStatus !=
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

              const Divider(height: kSpacingLarge),

              _TabSection(
                initialTabIndex: _beaconViewTabIndex(viewTab),
                timeline: state.timeline,
                commitments: state.commitments,
                forwardProvenance: state.forwardProvenance,
                inboxLatestNotePreview: state.inboxLatestNotePreview,
                myForwards: state.myForwards,
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
    required this.forwardProvenance,
    required this.inboxLatestNotePreview,
    required this.myForwards,
    required this.myUserId,
    required this.onEditCommitment,
    required this.isAuthorView,
    required this.onAuthorCoordination,
    this.initialTabIndex = 0,
  });

  final int initialTabIndex;
  final List<TimelineEntry> timeline;
  final List<TimelineCommitment> commitments;
  final InboxProvenance forwardProvenance;
  final String inboxLatestNotePreview;
  final List<ForwardEdge> myForwards;
  final String myUserId;
  final Future<void> Function(TimelineCommitment) onEditCommitment;
  final bool isAuthorView;
  final Future<void> Function(TimelineCommitment) onAuthorCoordination;

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
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.labelTimeline),
            Tab(text: l10n.labelCommitments),
            Tab(text: l10n.labelForwards),
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
          for (final entry in widget.timeline) _TimelineEntryTile(entry: entry),
        ] else if (_tabController.index == 1) ...[
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
          Padding(
            padding: kPaddingSmallV,
            child: Wrap(
              spacing: kSpacingSmall,
              runSpacing: kSpacingSmall,
              children: [
                BeaconCardPill(
                  label: l10n.beaconForwardsCount(
                    widget.forwardProvenance.totalDistinctSenders,
                  ),
                ),
              ],
            ),
          ),
          if (widget.forwardProvenance.senders.isEmpty)
            Padding(
              padding: kPaddingSmallV,
              child: Text(
                l10n.beaconForwardsEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            )
          else
            InboxForwardProvenancePanel(
              provenance: widget.forwardProvenance,
              latestNotePreview: widget.inboxLatestNotePreview,
            ),
          if (widget.myForwards.isNotEmpty) ...[
            const SizedBox(height: kSpacingMedium),
            _MyForwardsSection(edges: widget.myForwards),
          ],
        ],
      ],
    );
  }
}

class _MyForwardsSection extends StatelessWidget {
  const _MyForwardsSection({required this.edges});

  final List<ForwardEdge> edges;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.myForwardsSectionLabel,
          style: theme.textTheme.labelMedium?.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: kSpacingSmall),
        for (final edge in edges)
          Padding(
            padding: const EdgeInsets.only(bottom: kSpacingSmall),
            child: _MyForwardTile(edge: edge),
          ),
      ],
    );
  }
}

class _MyForwardTile extends StatelessWidget {
  const _MyForwardTile({required this.edge});

  final ForwardEdge edge;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final recipient = edge.recipient;
    final isDeclined = edge.recipientRejected;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: kPaddingAllS,
        child: Row(
          children: [
            AvatarRated(
              profile: recipient,
              withRating: false,
              size: 32,
            ),
            const SizedBox(width: kSpacingSmall),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recipient.title,
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (edge.note.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '"${edge.note}"',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (isDeclined) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.cancel_outlined,
                          size: 14,
                          color: scheme.error,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            edge.recipientRejectionMessage.isNotEmpty
                                ? l10n.myForwardDeclinedWithReason(
                                    edge.recipientRejectionMessage,
                                  )
                                : l10n.myForwardDeclined,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.error,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
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
