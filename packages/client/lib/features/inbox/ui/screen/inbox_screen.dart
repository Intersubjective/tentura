import 'package:flutter/material.dart';
import 'package:auto_route/auto_route.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widgets/app_choice_chip_style.dart';

import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/context/ui/bloc/context_cubit.dart';
import 'package:tentura/features/context/ui/widget/context_drop_down.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/enum.dart';
import '../bloc/inbox_cubit.dart';
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
          create: (_) => InboxCubit(
            initialContext: context.read<ContextCubit>().state.selected,
          ),
          child: MultiBlocListener(
            listeners: [
              BlocListener<ContextCubit, ContextState>(
                listenWhen: (p, c) => p.selected != c.selected,
                listener: (context, state) =>
                    context.read<InboxCubit>().fetch(contextName: state.selected),
              ),
              const BlocListener<InboxCubit, InboxState>(
                listener: commonScreenBlocListener,
              ),
            ],
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
      child: SafeArea(
        minimum: kPaddingSmallH,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const ContextDropDown(),
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
                              InboxSort.meritRank => l10n.inboxSortMeritRank,
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
            TabBar(
              automaticIndicatorColorAdjustment: false,
              labelColor: theme.colorScheme.primary,
              unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
              indicatorColor: theme.colorScheme.primary,
              dividerColor: theme.colorScheme.outlineVariant,
              tabs: [
                Tab(text: l10n.inboxTabNeedsMe),
                Tab(text: l10n.inboxTabWatching),
                Tab(text: l10n.inboxTabRejected),
              ],
            ),
            Expanded(
              child: BlocBuilder<InboxCubit, InboxState>(
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
                            style: theme.textTheme.titleMedium?.copyWith(
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
                      ),
                      _tabBody(
                        context,
                        inboxCubit,
                        state.watching,
                        l10n.inboxTabWatchingEmpty,
                        1,
                      ),
                      _tabBody(
                        context,
                        inboxCubit,
                        state.rejected,
                        l10n.inboxTabRejectedEmpty,
                        2,
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
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
    onRefresh: () => Future.wait([
      inboxCubit.fetch(),
      context.read<ContextCubit>().fetch(fromCache: false),
    ]),
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
    onRefresh: () => Future.wait([
      inboxCubit.fetch(),
      context.read<ContextCubit>().fetch(fromCache: false),
    ]),
    child: ListView.separated(
      padding: kPaddingSmallV,
      itemCount: items.length,
      separatorBuilder: (_, _) => const SizedBox(height: kSpacingSmall),
      itemBuilder: (_, i) {
        final item = items[i];
        return InboxItemTile(
          key: ValueKey(item.beaconId),
          item: item,
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
        );
      },
    ),
  );
}
