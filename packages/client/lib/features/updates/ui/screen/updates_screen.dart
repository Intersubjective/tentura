import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/updates_feed_cubit.dart';

@RoutePage()
/// Updates feed presenter.
class UpdatesScreen extends StatelessWidget {
  const UpdatesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => UpdatesFeedCubit(),
      child: const _UpdatesBody(),
    );
  }
}

class _UpdatesBody extends StatefulWidget {
  const _UpdatesBody();

  @override
  State<_UpdatesBody> createState() => _UpdatesBodyState();
}

class _UpdatesBodyState extends State<_UpdatesBody> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
  }

  void _loadMoreWhenNeeded() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - context.tt.sectionGap) {
      return;
    }
    unawaited(context.read<UpdatesFeedCubit>().loadNextPage());
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_loadMoreWhenNeeded)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return Scaffold(
      appBar: TenturaTopBar.of(
        context,
        title: Text(l10n.updatesTitle),
        actions: [
          BlocSelector<UpdatesFeedCubit, UpdatesFeedState, bool>(
            selector: (state) => state.items.any((item) => !item.isSeen),
            builder: (context, hasUnread) => TextButton(
              onPressed: hasUnread
                  ? () => context.read<UpdatesFeedCubit>().markAllSeen()
                  : null,
              child: Text(l10n.updatesMarkAllSeen),
            ),
          ),
        ],
      ),
      body: TenturaContentColumn(
        child: Column(
          children: [
            BlocSelector<UpdatesFeedCubit, UpdatesFeedState, AttentionView>(
              selector: (state) => state.view,
              builder: (context, view) => TenturaUnderlineTabs(
                tabs: [
                  l10n.updatesAll,
                  l10n.updatesUnread,
                  l10n.updatesNeedsYou,
                ],
                selectedIndex: view.index,
                onChanged: (index) => context.read<UpdatesFeedCubit>().setView(
                  AttentionView.values[index],
                ),
                tabIds: const ['updates-all', 'updates-unread'],
              ),
            ),
            Expanded(
              child: BlocBuilder<UpdatesFeedCubit, UpdatesFeedState>(
                builder: (context, state) {
                  if (state.isLoading && state.isEmpty) {
                    return const Center(
                      child: CircularProgressIndicator.adaptive(),
                    );
                  }
                  if (state.isEmpty) {
                    return _EmptyUpdates(view: state.view);
                  }
                  return RefreshIndicator.adaptive(
                    onRefresh: context.read<UpdatesFeedCubit>().refresh,
                    child: ListView.separated(
                      key: PageStorageKey<String>('updates-${state.view.name}'),
                      controller: _scrollController,
                      itemCount:
                          state.items.length + (state.hasNextPage ? 1 : 0),
                      separatorBuilder: (_, _) =>
                          const TenturaHairlineDivider(),
                      itemBuilder: (context, index) =>
                          index == state.items.length
                          ? const _LoadMoreIndicator()
                          : _UpdatesCard(receipt: state.items[index]),
                    ),
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

class _UpdatesCard extends StatelessWidget {
  const _UpdatesCard({required this.receipt});

  final AttentionReceipt receipt;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final colors = Theme.of(context).colorScheme;
    final isUnread = !receipt.isSeen;
    return Semantics(
      label: receipt.title,
      child: ListTile(
        onTap: () => _open(context),
        contentPadding: tt.cardPadding,
        leading: Icon(
          _iconFor(receipt.kind),
          color: isUnread ? tt.info : tt.textMuted,
          size: tt.iconSize,
        ),
        title: Text(
          receipt.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TenturaText.title(
            isUnread ? colors.onSurface : tt.textMuted,
          ).copyWith(fontWeight: isUnread ? FontWeight.w700 : FontWeight.w400),
        ),
        subtitle: Text(
          receipt.body,
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TenturaText.bodySmall(tt.textMuted),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _shortAge(receipt.createdAt),
              style: TenturaText.bodySmall(tt.textFaint),
            ),
            if (isUnread)
              IconButton(
                tooltip: L10n.of(context)!.updatesMarkSeen,
                onPressed: () => context.read<UpdatesFeedCubit>().markSeen(
                  receipt.id,
                ),
                icon: const Icon(Icons.done_outlined),
              ),
            if (receipt.isLiveObligation)
              IconButton(
                tooltip: L10n.of(context)!.updatesMarkDone,
                onPressed: () => context.read<UpdatesFeedCubit>().settle(
                  receipt.id,
                ),
                icon: const Icon(Icons.task_alt_outlined),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context) async {
    await context.read<UpdatesFeedCubit>().markSeen(receipt.id);
    await GetIt.I<RootRouter>().openFromUpdate(receipt);
  }

  static IconData _iconFor(String kind) => switch (kind) {
    'needsMe' || 'blockerOpened' => Icons.notifications_active_outlined,
    'roomActivityLowPriority' || 'newRelay' => Icons.forum_outlined,
    'inviteAccepted' => Icons.people_alt_outlined,
    _ => Icons.notifications_outlined,
  };

  static String _shortAge(DateTime at) {
    final age = DateTime.now().difference(at);
    if (age.inMinutes < 1) return 'now';
    if (age.inHours < 1) return '${age.inMinutes}m';
    if (age.inDays < 1) return '${age.inHours}h';
    return '${age.inDays}d';
  }
}

class _EmptyUpdates extends StatelessWidget {
  const _EmptyUpdates({required this.view});

  final AttentionView view;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Center(
      child: Padding(
        padding: tt.cardPadding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_outlined,
              size: tt.iconSize * 2,
              color: tt.textFaint,
            ),
            SizedBox(height: tt.rowGap),
            Text(l10n.updatesEmptyTitle, style: TenturaText.title(tt.text)),
            SizedBox(height: tt.tightGap),
            Text(
              view == AttentionView.all
                  ? l10n.updatesEmptyAllHint
                  : view == AttentionView.unread
                  ? l10n.updatesEmptyUnreadHint
                  : l10n.updatesEmptyNeedsYouHint,
              textAlign: TextAlign.center,
              style: TenturaText.bodySmall(tt.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreIndicator extends StatelessWidget {
  const _LoadMoreIndicator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: context.tt.cardPadding,
    child: const Center(child: CircularProgressIndicator.adaptive()),
  );
}
