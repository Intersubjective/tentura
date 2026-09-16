import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_summary.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../bloc/updates_feed_cubit.dart';
import 'invite_accepted_receipt_card.dart';
import 'trust_change_receipt_card.dart';
import 'prompt_batch_sheet.dart';
import 'updates_day_groups.dart';
import 'updates_feed_app_bar.dart';
import 'updates_feed_search_field.dart';
import 'updates_receipt_card.dart';
import 'updates_refresh_error_banner.dart';

/// Shared Updates / receipts feed body (All / Unread; Needs you in My Work only).
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
  ];

  final bool showTitleRow;
  final List<AttentionView> offeredViews;
  final bool showViewControl;

  @override
  State<UpdatesFeedPane> createState() => _UpdatesFeedPaneState();
}

class _UpdatesFeedPaneState extends State<UpdatesFeedPane>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _searchController = TextEditingController();
  Timer? _searchDebounce;
  var _searchOpen = false;
  var _restoredSearchText = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_loadMoreWhenNeeded);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
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
    WidgetsBinding.instance.removeObserver(this);
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
              final now = DateTime.now();
              final placement = computeInvitePromptPinPlacement(
                items: state.items,
                state: state,
                now: now,
              );
              final hasScrollBody = _updatesFeedHasScrollBody(
                state: state,
                placement: placement,
              );
              if (state.isLoading && state.isEmpty && !hasScrollBody) {
                return const Center(
                  child: CircularProgressIndicator.adaptive(),
                );
              }
              if (!hasScrollBody) {
                return _EmptyUpdates(view: state.view);
              }
              final chronologicalItems = state.items
                  .where((r) => !placement.liftedReceiptIds.contains(r.id))
                  .toList(growable: false);
              final cells = flattenUpdatesFeed(
                items: chronologicalItems,
                hasNextPage: state.hasNextPage,
              );
              final cubit = context.read<UpdatesFeedCubit>();
              return RefreshIndicator.adaptive(
                onRefresh: cubit.refresh,
                child: CustomScrollView(
                  key: PageStorageKey<String>('updates-${state.view.name}'),
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    if (state.hasRefreshError)
                      SliverToBoxAdapter(
                        child: UpdatesRefreshErrorBanner(
                          onRetry: () => unawaited(cubit.refresh()),
                        ),
                      ),
                    if (placement.pinnedReceipts.isNotEmpty)
                      SliverList.builder(
                        itemCount: placement.pinnedReceipts.length,
                        itemBuilder: (context, index) {
                          final receipt = placement.pinnedReceipts[index];
                          return KeyedSubtree(
                            key: TestIds.key(
                              TestIds.activityPromptPin(receipt.id),
                            ),
                            child: _receiptRow(context, receipt),
                          );
                        },
                      ),
                    if (placement.collapsedCount >= 3)
                      SliverToBoxAdapter(
                        child: _CollapsedInvitePromptRow(
                          count: placement.collapsedCount,
                          onOpenBatch: () => unawaited(
                            PromptBatchSheet.show(
                              context: context,
                              cubit: cubit,
                              receipts: placement.collapsedReceipts,
                            ),
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
              locale: Localizations.localeOf(context),
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
    final actors = context.read<UpdatesFeedCubit>().state.actors;
    final actorId = receipt.actorUserId?.trim() ?? '';
    final actor = actorId.isEmpty ? null : actors[actorId];
    if (isTrustChangePresentationKey(receipt.presentationKey)) {
      return TrustChangeReceiptCard(
        key: ValueKey(receipt.id),
        receipt: receipt,
        actor: actor,
        onTap: onTap,
        onMarkSeen: onMarkSeen,
        onMarkUnseen: onMarkUnseen,
        onSettle: onSettle,
      );
    }
    if (isInviteAcceptedPresentationKey(receipt.presentationKey)) {
      final subjectId = receipt.actorUserId ?? receipt.targetEntityId;
      return BlocSelector<UpdatesFeedCubit, UpdatesFeedState, PromptProjection>(
        selector: (state) => subjectId == null
            ? const PromptProjection.unknown()
            : state.promptProjectionFor(subjectId),
        builder: (context, projection) {
          final cubit = context.read<UpdatesFeedCubit>();
          return InviteAcceptedReceiptCard(
            key: ValueKey(receipt.id),
            receipt: receipt,
            promptProjection: projection,
            onRetryPromptFetch: cubit.retryPromptFetch,
            onPromptSettled: cubit.applyKnownPrompt,
            onTap: onTap,
            onMarkSeen: () => cubit.markSeen(receipt.id),
            onMarkUnseen: onMarkUnseen,
          );
        },
      );
    }
    return UpdatesReceiptCard(
      key: ValueKey(receipt.id),
      receipt: receipt,
      actor: actor,
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

bool _updatesFeedHasScrollBody({
  required UpdatesFeedState state,
  required InvitePromptPinPlacement placement,
}) {
  if (state.hasRefreshError) return true;
  if (placement.pinnedReceipts.isNotEmpty) return true;
  if (placement.collapsedCount >= 3) return true;
  return !state.isEmpty;
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

class _CollapsedInvitePromptRow extends StatelessWidget {
  const _CollapsedInvitePromptRow({
    required this.count,
    required this.onOpenBatch,
  });

  final int count;
  final VoidCallback onOpenBatch;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    final label = l10n.activityPromptCollapsedBatch(count);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.listRowPadding.left,
        tt.tightGap,
        tt.listRowPadding.right,
        tt.tightGap,
      ),
      child: TenturaAttentionSummaryRow(
        label: label,
        maxLines: 2,
        showChevron: false,
        semanticsLabel: label,
        inkWellKey: TestIds.key(TestIds.activityPromptCollapsed),
        onTap: onOpenBatch,
      ),
    );
  }
}

/// Fresh pending invite prompts are younger than 7 local calendar days.
bool isFreshInvitePromptReceipt({
  required DateTime createdAt,
  required DateTime now,
}) =>
    now.difference(createdAt.toLocal()).inDays < 7;

/// Pin placement for architecture §5.5 / §5.5.1 (exclusive pin vs collapsed modes).
InvitePromptPinPlacement computeInvitePromptPinPlacement({
  required List<AttentionReceipt> items,
  required UpdatesFeedState state,
  required DateTime now,
}) {
  final candidates = <AttentionReceipt>[];
  for (final receipt in items) {
    if (!state.canPinInvitePrompt(receipt)) continue;
    if (!isFreshInvitePromptReceipt(createdAt: receipt.createdAt, now: now)) {
      continue;
    }
    candidates.add(receipt);
  }
  candidates.sort(_invitePromptPinSort);

  if (candidates.length >= 3) {
    return InvitePromptPinPlacement(
      pinnedReceipts: const [],
      collapsedReceipts: List<AttentionReceipt>.from(candidates),
      collapsedCount: candidates.length,
      liftedReceiptIds: {for (final r in candidates) r.id},
    );
  }
  return InvitePromptPinPlacement(
    pinnedReceipts: List<AttentionReceipt>.from(candidates),
    collapsedReceipts: const [],
    collapsedCount: 0,
    liftedReceiptIds: {for (final r in candidates) r.id},
  );
}

int _invitePromptPinSort(AttentionReceipt a, AttentionReceipt b) {
  final byTime = b.createdAt.compareTo(a.createdAt);
  if (byTime != 0) return byTime;
  return b.id.compareTo(a.id);
}

class InvitePromptPinPlacement {
  const InvitePromptPinPlacement({
    required this.pinnedReceipts,
    required this.collapsedReceipts,
    required this.collapsedCount,
    required this.liftedReceiptIds,
  });

  final List<AttentionReceipt> pinnedReceipts;
  final List<AttentionReceipt> collapsedReceipts;
  final int collapsedCount;
  final Set<String> liftedReceiptIds;
}
