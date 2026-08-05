import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/updates_feed_cubit.dart';
import '../widget/updates_receipt_card.dart';

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
  final _searchController = TextEditingController();
  Timer? _searchDebounce;

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
    _searchDebounce?.cancel();
    _searchController.dispose();
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
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.tt.screenHPadding,
              ),
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: l10n.updatesSearchHint,
                  prefixIcon: const Icon(Icons.search_outlined),
                  suffixIcon: _searchController.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).deleteButtonTooltip,
                          icon: const Icon(Icons.clear_outlined),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                ),
              ),
            ),
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
                          : UpdatesReceiptCard(
                              receipt: state.items[index],
                              onTap: () => _open(context, state.items[index]),
                              onMarkSeen: () => context
                                  .read<UpdatesFeedCubit>()
                                  .markSeen(state.items[index].id),
                              onSettle: () => context
                                  .read<UpdatesFeedCubit>()
                                  .settle(state.items[index].id),
                            ),
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

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) context.read<UpdatesFeedCubit>().setSearch(value);
    });
    setState(() {});
  }

  Future<void> _open(BuildContext context, AttentionReceipt receipt) async {
    await context.read<UpdatesFeedCubit>().markSeen(receipt.id);
    await GetIt.I<RootRouter>().openFromUpdate(receipt);
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
