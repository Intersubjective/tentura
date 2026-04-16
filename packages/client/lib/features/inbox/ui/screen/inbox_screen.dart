import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_status.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widgets/app_choice_chip_style.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/bloc/new_stuff_cubit.dart';
import 'package:tentura/features/beacon_view/ui/dialog/commitment_message_dialog.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import '../bloc/inbox_cubit.dart';
import '../message/inbox_messages.dart';
import '../widget/inbox_item_tile.dart';
import '../widget/inbox_tombstone_card.dart';
import '../widget/rejection_dialog.dart';

@RoutePage()
class InboxScreen extends StatelessWidget implements AutoRouteWrapper {
  const InboxScreen({super.key});

  @override
  Widget wrappedRoute(BuildContext context) =>
      BlocSelector<AuthCubit, AuthState, String>(
        bloc: GetIt.I<AuthCubit>(),
        selector: (state) => state.currentAccountId,
        builder: (_, accountId) => BlocProvider(
          key: ValueKey(accountId),
          create: (_) => InboxCubit(userId: accountId),
          child: BlocListener<InboxCubit, InboxState>(
            listener: (context, state) {
              final s = state.status;
              if (s is StateIsMessaging &&
                  s.message is InboxBeaconMovedMessage) {
                return;
              }
              commonScreenBlocListener(context, state);
            },
            child: this,
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final inboxCubit = context.read<InboxCubit>();

    return DefaultTabController(
      length: 3,
      child: BlocListener<HomeTabReselectCubit, HomeTabReselectState>(
        listenWhen: (prev, curr) =>
            prev.inboxReselectCount != curr.inboxReselectCount,
        listener: (context, _) {
          inboxCubit.setSort(InboxSort.recent);
          DefaultTabController.of(context).animateTo(0);
        },
        child: BlocListener<InboxCubit, InboxState>(
          listenWhen: (prev, curr) =>
              curr.status is StateIsMessaging &&
              (curr.status as StateIsMessaging).message
                  is InboxBeaconMovedMessage,
          listener: (context, state) {
            final msg =
                (state.status as StateIsMessaging).message
                    as InboxBeaconMovedMessage;
            final l10n = L10n.of(context)!;
            showSnackBar(
              context,
              text: msg.toL10n(l10n.localeName),
              action: SnackBarAction(
                label: l10n.inboxViewInTab,
                onPressed: () {
                  DefaultTabController.of(context).animateTo(msg.tabIndex);
                },
              ),
            );
          },
          child: SafeArea(
            minimum: kPaddingSmallH,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                BlocSelector<InboxCubit, InboxState, InboxSort>(
                  selector: (state) => state.sort,
                  builder: (_, sort) {
                    final chipStyle = AppChoiceChipStyle(theme.colorScheme);
                    return Padding(
                      padding: kPaddingSmallV,
                      child: Wrap(
                        spacing: kSpacingSmall,
                        children: [
                          for (final s in InboxSort.values)
                            ChoiceChip(
                              color: chipStyle.background,
                              labelStyle: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w500,
                                color: chipStyle.labelForeground,
                              ),
                              checkmarkColor: chipStyle.checkmarkColor,
                              side: chipStyle.outline,
                              selected: sort == s,
                              label: Text(
                                switch (s) {
                                  InboxSort.recent => l10n.inboxSortRecent,
                                  InboxSort.meritRank =>
                                    l10n.inboxSortMeritRank,
                                  InboxSort.deadline => l10n.inboxSortDeadline,
                                },
                              ),
                              onSelected: (_) => inboxCubit.setSort(s),
                            ),
                        ],
                      ),
                    );
                  },
                ),
                BlocSelector<InboxCubit, InboxState, (int, int)>(
                  selector: (state) =>
                      (state.needsMe.length, state.watching.length),
                  builder: (_, counts) => TabBar(
                    automaticIndicatorColorAdjustment: false,
                    labelColor: theme.colorScheme.primary,
                    unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
                    indicatorColor: theme.colorScheme.primary,
                    dividerColor: theme.colorScheme.outlineVariant,
                    tabs: [
                      Tab(
                        text: counts.$1 > 0
                            ? '${l10n.inboxTabNeedsMe} (${counts.$1})'
                            : l10n.inboxTabNeedsMe,
                      ),
                      Tab(
                        text: counts.$2 > 0
                            ? '${l10n.inboxTabWatching} (${counts.$2})'
                            : l10n.inboxTabWatching,
                      ),
                      Tab(text: l10n.inboxTabRejected),
                    ],
                  ),
                ),
                Expanded(
                  child: BlocBuilder<NewStuffCubit, NewStuffState>(
                    buildWhen: (p, c) =>
                        p.inboxLastSeenMs != c.inboxLastSeenMs ||
                        p.maxInboxActivityMs != c.maxInboxActivityMs,
                    builder: (context, _) {
                      final newStuff = context.read<NewStuffCubit>();
                      return BlocBuilder<InboxCubit, InboxState>(
                        buildWhen: (_, c) =>
                            c.isSuccess || c.isLoading || c.hasError,
                        builder: (_, state) {
                          if (state.isLoading) {
                            return const Center(
                              child: CircularProgressIndicator.adaptive(),
                            );
                          }
                          if (state.items.isEmpty) {
                            return Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.inbox_outlined,
                                    size: 64,
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                  const SizedBox(height: kSpacingMedium),
                                  Text(
                                    l10n.inboxEmpty,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: kSpacingSmall),
                                  Text(
                                    l10n.inboxEmptyHint,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }
                          return TabBarView(
                            children: [
                              _needsMeTabBody(
                                context,
                                inboxCubit,
                                state,
                                l10n,
                                newStuff,
                              ),
                              _tabBody(
                                context,
                                inboxCubit,
                                state.watching,
                                l10n.inboxTabWatchingEmpty,
                                1,
                                newStuff,
                              ),
                              _tabBody(
                                context,
                                inboxCubit,
                                state.rejected,
                                l10n.inboxTabRejectedEmpty,
                                2,
                                newStuff,
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _needsMeTabBody(
  BuildContext context,
  InboxCubit inboxCubit,
  InboxState state,
  L10n l10n,
  NewStuffCubit newStuff,
) {
  final theme = Theme.of(context);
  final tombstones = state.tombstonesLast24h;
  final needsMe = state.needsMe;

  if (tombstones.isEmpty && needsMe.isEmpty) {
    return Center(
      child: Text(
        l10n.inboxTabNeedsEmpty,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  return RefreshIndicator.adaptive(
    onRefresh: () => inboxCubit.fetch(),
    child: CustomScrollView(
      slivers: [
        if (tombstones.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: kPaddingSmallV,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.inboxTombstoneQueueStatus,
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.2,
                          color: theme.colorScheme.outline,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.inboxTombstoneSectionTitle,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHigh,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      l10n.inboxTombstoneLast24h,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          SliverList.separated(
            itemCount: tombstones.length,
            separatorBuilder: (_, _) => const SizedBox(height: kSpacingSmall),
            itemBuilder: (_, i) {
              final item = tombstones[i];
              return Padding(
                padding: kPaddingSmallH,
                child: InboxTombstoneCard(
                  key: ValueKey('tombstone-${item.beaconId}'),
                  item: item,
                  onOpen: () => context.router.pushPath(
                    '$kPathBeaconView/${item.beaconId}',
                  ),
                  onDismiss: () => inboxCubit.dismissTombstone(item.beaconId),
                ),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: kSpacingMedium)),
        ],
        if (needsMe.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: kPaddingSmallH.add(kPaddingSmallV),
              child: Text(
                l10n.inboxTabNeedsMe,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          SliverList.separated(
            itemCount: needsMe.length,
            separatorBuilder: (_, _) => const SizedBox(height: kSpacingSmall),
            itemBuilder: (_, i) {
              final item = needsMe[i];
              return Padding(
                padding: kPaddingSmallH,
                child: InboxItemTile(
                  key: ValueKey(item.beaconId),
                  item: item,
                  inboxHighlight: newStuff.inboxRowHighlight(
                    latestForwardAt: item.latestForwardAt,
                    forwardCount: item.forwardCount,
                    beaconActivityEpochMs: item.newStuffBeaconOnlyActivityEpochMs,
                  ),
                  onOpenBeacon: () => context.router.pushPath(
                    '$kPathBeaconView/${item.beaconId}',
                  ),
                  onTap: () => context.router.pushPath(
                    '$kPathForwardBeacon/${item.beaconId}',
                  ),
                  onWatch: () => inboxCubit.setWatching(item.beaconId),
                  onCantHelp: () async {
                    final msg = await showRejectionDialog(context);
                    if (!context.mounted) return;
                    if (msg != null) {
                      await inboxCubit.reject(item.beaconId, message: msg);
                    }
                  },
                  onCommit: _inboxCardAllowsCommit(item)
                      ? () => _inboxCommit(context, item.beacon!)
                      : null,
                ),
              );
            },
          ),
        ] else if (tombstones.isNotEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: kPaddingSmallH.add(const EdgeInsets.only(top: 8)),
              child: Text(
                l10n.inboxTabNeedsEmpty,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    ),
  );
}

Widget _tabBody(
  BuildContext context,
  InboxCubit inboxCubit,
  List<InboxItem> items,
  String emptyHint,
  int tabIndex,
  NewStuffCubit newStuff,
) {
  final theme = Theme.of(context);

  if (items.isEmpty) {
    return Center(
      child: Text(
        emptyHint,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  return RefreshIndicator.adaptive(
    onRefresh: () => inboxCubit.fetch(),
    child: ListView.separated(
      padding: kPaddingSmallV,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: kSpacingSmall),
      itemBuilder: (_, i) {
        final item = items[i];
        return InboxItemTile(
          key: ValueKey(item.beaconId),
          item: item,
          inboxHighlight: newStuff.inboxRowHighlight(
            latestForwardAt: item.latestForwardAt,
            forwardCount: item.forwardCount,
            beaconActivityEpochMs: item.newStuffBeaconOnlyActivityEpochMs,
          ),
          onOpenBeacon: () => context.router.pushPath(
            '$kPathBeaconView/${item.beaconId}',
          ),
          onTap: () => context.router.pushPath(
            '$kPathForwardBeacon/${item.beaconId}',
          ),
          onWatch: tabIndex == 0
              ? () => inboxCubit.setWatching(item.beaconId)
              : null,
          onStopWatching: tabIndex == 1
              ? () => inboxCubit.stopWatching(item.beaconId)
              : null,
          onCantHelp: tabIndex == 0 || tabIndex == 1
              ? () async {
                  final msg = await showRejectionDialog(context);
                  if (!context.mounted) return;
                  if (msg != null) {
                    await inboxCubit.reject(item.beaconId, message: msg);
                  }
                }
              : null,
          onMoveToInbox: tabIndex == 2
              ? () => inboxCubit.unreject(item.beaconId)
              : null,
          onCommit: _inboxCardAllowsCommit(item)
              ? () => _inboxCommit(context, item.beacon!)
              : null,
          showCtaRow: false,
          showProvenance: false,
        );
      },
    ),
  );
}

bool _inboxCardAllowsCommit(InboxItem item) {
  final b = item.beacon;
  return b != null &&
      b.allowsNewCommitAsNonAuthor &&
      item.status != InboxItemStatus.rejected;
}

Future<void> _inboxCommit(BuildContext context, Beacon beacon) async {
  final l10n = L10n.of(context)!;
  final useCommitAnyway =
      beacon.coordinationStatus == BeaconCoordinationStatus.enoughHelpCommitted;
  final outcome = await CommitmentMessageDialog.show(
    context,
    title: useCommitAnyway
        ? l10n.dialogCommitAnywayTitle
        : l10n.dialogCommitTitle,
    hintText: l10n.hintCommitMessage,
    allowEmptyMessage: true,
    showHelpTypeChips: true,
  );
  if (outcome == null || !context.mounted) return;
  await GetIt.I<ForwardRepository>().commit(
    beaconId: beacon.id,
    message: outcome.message,
    helpType: outcome.helpTypeWire,
  );
}
