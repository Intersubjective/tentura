import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/app/router/root_router.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/updates_feed_cubit.dart';
import '../widget/invite_accepted_receipt_card.dart';
import '../widget/trust_change_receipt_card.dart';
import '../widget/updates_day_groups.dart';
import '../widget/updates_feed_app_bar.dart';
import '../widget/updates_feed_search_field.dart';
import '../widget/updates_receipt_card.dart';
import '../widget/updates_refresh_error_banner.dart';

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
  var _searchOpen = false;

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
    final tt = context.tt;
    final compact = context.windowClass == WindowClass.compact;
    final showSearchField = !compact || _searchOpen;
    final hasUnread = context.select<UpdatesFeedCubit, bool>(
      (cubit) => cubit.state.summary.unreadTotal > 0,
    );

    return Scaffold(
      backgroundColor: tt.bg,
      appBar: TenturaTopBar.of(
        context,
        title: const SizedBox.shrink(),
        row: UpdatesFeedAppBarRow(
          title: l10n.updatesTitle,
          markAllLabel: l10n.updatesMarkAllSeen,
          hasUnread: hasUnread,
          onMarkAll: () => context.read<UpdatesFeedCubit>().markAllSeen(),
          showSearchIcon: compact,
          searchOpen: _searchOpen,
          onSearchPressed: () => setState(() => _searchOpen = !_searchOpen),
          searchTooltip: l10n.updatesSearchHint,
        ),
      ),
      body: TenturaContentColumn(
        child: Column(
          children: [
            if (showSearchField)
              UpdatesFeedSearchField(
                controller: _searchController,
                hintText: l10n.updatesSearchHint,
                onChanged: _onSearchChanged,
                onClear: () {
                  _searchController.clear();
                  _onSearchChanged('');
                },
              ),
            BlocBuilder<UpdatesFeedCubit, UpdatesFeedState>(
              buildWhen: (p, c) =>
                  p.view != c.view || p.summary != c.summary,
              builder: (context, state) => TenturaUnderlineTabs(
                tabs: [
                  l10n.updatesAll,
                  l10n.updatesUnread,
                  l10n.updatesNeedsYou,
                ],
                selectedIndex: state.view.index,
                onChanged: (index) => context.read<UpdatesFeedCubit>().setView(
                  AttentionView.values[index],
                ),
                badges: [
                  null,
                  state.summary.unreadTotal,
                  state.summary.needsYouTotal,
                ],
                countStyle: TenturaTabCountStyle.plainText,
                tabIds: const [
                  'updates-all',
                  'updates-unread',
                  'updates-needs-you',
                ],
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
                  final cells = flattenUpdatesFeed(
                    items: state.items,
                    hasNextPage: state.hasNextPage,
                  );
                  return RefreshIndicator.adaptive(
                    onRefresh: context.read<UpdatesFeedCubit>().refresh,
                    child: CustomScrollView(
                      key: PageStorageKey<String>('updates-${state.view.name}'),
                      controller: _scrollController,
                      physics: const AlwaysScrollableScrollPhysics(),
                      slivers: [
                        if (state.hasRefreshError)
                          SliverToBoxAdapter(
                            child: UpdatesRefreshErrorBanner(
                              onRetry: () => unawaited(
                                context.read<UpdatesFeedCubit>().refresh(),
                              ),
                            ),
                          ),
                        SliverList.builder(
                          itemCount: cells.length,
                          itemBuilder: (context, index) {
                            return _cellWidget(context, cells[index]);
                          },
                        ),
                      ],
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

  Widget _cellWidget(BuildContext context, UpdatesFeedCell cell) {
    final l10n = L10n.of(context)!;
    switch (cell.kind) {
      case UpdatesFeedCellKind.header:
        return Padding(
          padding: EdgeInsets.fromLTRB(
            context.tt.listRowPadding.left,
            context.tt.rowGap,
            context.tt.listRowPadding.right,
            context.tt.tightGap,
          ),
          child: Text(
            updatesDayHeaderLabel(
              day: cell.day!,
              now: DateTime.now(),
              l10n: l10n,
            ).toUpperCase(),
            style: TenturaText.typeLabel(context.tt.textFaint),
          ),
        );
      case UpdatesFeedCellKind.loadMore:
        return const _LoadMoreIndicator();
      case UpdatesFeedCellKind.row:
        final receipt = cell.receipt!;
        final row = _receiptRow(context, receipt);
        if (!cell.showDividerBelow) return row;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [row, const TenturaHairlineDivider()],
        );
    }
  }

  Widget _receiptRow(BuildContext context, AttentionReceipt receipt) {
    void onTap() => _open(context, receipt);
    void onMarkSeen() =>
        unawaited(context.read<UpdatesFeedCubit>().markSeen(receipt.id));
    void onSettle() =>
        unawaited(context.read<UpdatesFeedCubit>().settle(receipt.id));
    if (isTrustChangePresentationKey(receipt.presentationKey)) {
      return TrustChangeReceiptCard(
        key: ValueKey(receipt.id),
        receipt: receipt,
        onTap: onTap,
        onMarkSeen: onMarkSeen,
        onSettle: onSettle,
      );
    }
    if (isInviteAcceptedPresentationKey(receipt.presentationKey)) {
      return InviteAcceptedReceiptCard(
        key: ValueKey(receipt.id),
        receipt: receipt,
        onTap: onTap,
        onMarkSeen: () => context.read<UpdatesFeedCubit>().markSeen(receipt.id),
      );
    }
    return UpdatesReceiptCard(
      key: ValueKey(receipt.id),
      receipt: receipt,
      onTap: onTap,
      onMarkSeen: onMarkSeen,
      onSettle: onSettle,
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
    unawaited(context.read<UpdatesFeedCubit>().markSeen(receipt.id));
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
    final text = view == AttentionView.needsYou
        ? l10n.updatesEmptyNeedsYouHint
        : view == AttentionView.unread
        ? l10n.updatesEmptyUnreadHint
        : l10n.updatesEmptyAllHint;
    return Center(
      child: Padding(
        padding: tt.cardPadding,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TenturaText.bodySmall(tt.textMuted),
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
