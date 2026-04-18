import 'dart:async';

import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/beacon_card_primitives.dart';
import 'package:tentura/ui/widget/collapsible_section.dart';
import 'package:tentura/ui/widget/linear_pi_active.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_close_confirm_dialog.dart';
import 'package:tentura/features/beacon/ui/dialog/beacon_delete_dialog.dart';
import 'package:tentura/features/beacon/ui/widget/beacon_info.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/evaluation/ui/widget/beacon_evaluation_hooks.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/widget/rejection_dialog.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/dialog/share_code_dialog.dart';
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
          value: 'view_forwards',
          child: _beaconOverflowMenuRow(
            Icons.forward_to_inbox,
            l10n.labelForwards,
          ),
        ),
      )
      ..add(
        PopupMenuItem(
          value: 'delete',
          child: _beaconOverflowMenuRow(
            Icons.delete_outline,
            l10n.deleteBeacon,
          ),
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
  items
    ..add(
      PopupMenuItem(
        value: 'forward',
        child: _beaconOverflowMenuRow(Icons.send, l10n.labelForward),
      ),
    )
    ..add(
      PopupMenuItem(
        value: 'view_forwards',
        child: _beaconOverflowMenuRow(
          Icons.forward_to_inbox,
          l10n.labelForwards,
        ),
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
    case 'view_forwards':
      if (context.mounted) {
        await context.router.pushPath('$kPathBeaconForwards/$beaconId');
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
          if (state.isLoading &&
              state.timeline.isEmpty &&
              state.commitments.isEmpty) {
            return const Center(
              child: CircularProgressIndicator.adaptive(),
            );
          }
          final beacon = state.beacon;
          final theme = Theme.of(context);
          final updates = state.timeline.whereType<TimelineUpdate>().toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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

              CollapsibleSection(
                title: l10n.beaconUpdatesSection,
                initiallyExpanded: updates.isNotEmpty,
                badge: updates.isEmpty ? null : '${updates.length}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (updates.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          vertical: kSpacingSmall,
                        ),
                        child: Text(
                          l10n.beaconUpdatesEmpty,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    else
                      ...updates.map(
                        (u) => ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            l10n.updateNumberLabel(u.number),
                            style: theme.textTheme.labelLarge,
                          ),
                          subtitle: Text(
                            u.content,
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall,
                          ),
                          trailing:
                              state.isBeaconMine &&
                                  beacon.lifecycle == BeaconLifecycle.open
                              ? IconButton(
                                  tooltip: l10n.editUpdateCTA,
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => unawaited(
                                    _showEditAuthorUpdateSheet(
                                      context,
                                      beaconViewCubit,
                                      l10n,
                                      initial: u.content,
                                      updateId: u.id,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ),
                    if (state.isBeaconMine &&
                        beacon.lifecycle == BeaconLifecycle.open)
                      Padding(
                        padding: const EdgeInsets.only(top: kSpacingSmall),
                        child: FilledButton.icon(
                          icon: const Icon(Icons.campaign_outlined),
                          label: Text(l10n.postUpdateCTA),
                          onPressed: () => unawaited(
                            _showPostAuthorUpdateSheet(
                              context,
                              beaconViewCubit,
                              l10n,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

              BeaconEvaluationHooks(
                beaconId: beacon.id,
                lifecycle: beacon.lifecycle,
              ),

              const SizedBox(height: kSpacingMedium),

              _TabSection(
                initialTabIndex: _beaconViewTabIndex(viewTab),
                beacon: beacon,
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
    required this.beacon,
    required this.timeline,
    required this.commitments,
    required this.myUserId,
    required this.onEditCommitment,
    required this.isAuthorView,
    required this.onAuthorCoordination,
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
}) async {
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
  const _TimelineEntryTile({required this.entry});

  final TimelineEntry entry;

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
