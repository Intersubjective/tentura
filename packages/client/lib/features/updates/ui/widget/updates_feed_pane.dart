import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/updates_feed_cubit.dart';
import 'invite_accepted_receipt_card.dart';
import 'trust_change_receipt_card.dart';
import 'updates_day_groups.dart';
import 'updates_feed_app_bar.dart';
import 'updates_feed_search_field.dart';
import 'updates_receipt_card.dart';
import 'updates_refresh_error_banner.dart';

/// Shared Updates / receipts feed body (All / Unread / Needs you).
///
/// Embedded inside Inbox's Receipts tab; [showTitleRow] hides the duplicate
/// title when the parent screen already owns the tab strip.
class UpdatesFeedPane extends StatefulWidget {
  const UpdatesFeedPane({
    this.showTitleRow = false,
    this.offeredViews = kDefaultUpdatesFeedOfferedViews,
    this.showViewControl = true,
    super.key,
  });

  static const kDefaultUpdatesFeedOfferedViews = <AttentionView>[
    AttentionView.all,
    AttentionView.unread,
    AttentionView.needsYou,
  ];

  final bool showTitleRow;
  final List<AttentionView> offeredViews;
  final bool showViewControl;

  @override
  State<UpdatesFeedPane> createState() => _UpdatesFeedPaneState();
}

class _UpdatesFeedPaneState extends State<UpdatesFeedPane> {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  var _searchOpen = false;
  var _restoredSearchText = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_loadMoreWhenNeeded);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_restoredSearchText) {
      _restoredSearchText = true;
      final saved = context.read<UpdatesFeedCubit>().state.searchText;
      if (saved.isNotEmpty) {
        _searchController.text = saved;
      }
    }
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

    return Column(
      children: [
        if (widget.showTitleRow)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tt.listRowPadding.left),
            child: UpdatesFeedAppBarRow(
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
        if (!widget.showTitleRow)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: EdgeInsets.only(
                right: tt.listRowPadding.right,
                top: tt.tightGap,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TenturaTextAction(
                    label: l10n.updatesMarkAllSeen,
                    onPressed: hasUnread
                        ? () => context.read<UpdatesFeedCubit>().markAllSeen()
                        : null,
                  ),
                  if (compact)
                    IconButton(
                      tooltip: l10n.updatesSearchHint,
                      isSelected: _searchOpen,
                      onPressed: () =>
                          setState(() => _searchOpen = !_searchOpen),
                      icon: const Icon(Icons.search),
                    ),
                ],
              ),
            ),
          ),
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
        if (widget.showViewControl && widget.offeredViews.length > 1)
          BlocBuilder<UpdatesFeedCubit, UpdatesFeedState>(
            buildWhen: (p, c) => p.view != c.view || p.summary != c.summary,
            builder: (context, state) {
              final views = widget.offeredViews;
              final selectedIndex = views.indexOf(state.view).clamp(
                0,
                views.length - 1,
              );
              return TenturaUnderlineTabs(
                tabs: [
                  for (final view in views) _labelForView(l10n, view),
                ],
                selectedIndex: selectedIndex,
                onChanged: (index) => context.read<UpdatesFeedCubit>().setView(
                  views[index],
                ),
                badges: [
                  for (final view in views) _badgeForView(state.summary, view),
                ],
                countStyle: TenturaTabCountStyle.plainText,
                tabIds: [
                  for (final view in views) _tabIdForView(view),
                ],
              );
            },
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
    void onMarkUnseen() =>
        unawaited(context.read<UpdatesFeedCubit>().markUnseen(receipt.id));
    void onSettle() =>
        unawaited(context.read<UpdatesFeedCubit>().settle(receipt.id));
    if (isTrustChangePresentationKey(receipt.presentationKey)) {
      return TrustChangeReceiptCard(
        key: ValueKey(receipt.id),
        receipt: receipt,
        onTap: onTap,
        onMarkSeen: onMarkSeen,
        onMarkUnseen: onMarkUnseen,
        onSettle: onSettle,
      );
    }
    if (isInviteAcceptedPresentationKey(receipt.presentationKey)) {
      return InviteAcceptedReceiptCard(
        key: ValueKey(receipt.id),
        receipt: receipt,
        onTap: onTap,
        onMarkSeen: () => context.read<UpdatesFeedCubit>().markSeen(receipt.id),
        onMarkUnseen: onMarkUnseen,
      );
    }
    return UpdatesReceiptCard(
      key: ValueKey(receipt.id),
      receipt: receipt,
      onTap: onTap,
      onMarkSeen: onMarkSeen,
      onMarkUnseen: onMarkUnseen,
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

String _labelForView(L10n l10n, AttentionView view) => switch (view) {
  AttentionView.all => l10n.updatesAll,
  AttentionView.unread => l10n.updatesUnread,
  AttentionView.needsYou => l10n.updatesNeedsYou,
};

int? _badgeForView(AttentionSummary summary, AttentionView view) =>
    switch (view) {
      AttentionView.all => null,
      AttentionView.unread => summary.unreadTotal,
      AttentionView.needsYou => summary.needsYouTotal,
    };

String _tabIdForView(AttentionView view) => switch (view) {
  AttentionView.all => 'updates-all',
  AttentionView.unread => 'updates-unread',
  AttentionView.needsYou => 'updates-needs-you',
};

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
