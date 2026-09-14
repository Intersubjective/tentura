import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/design_system/components/tentura_attention_summary_row.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/prompt_batch_sheet.dart';
import 'package:tentura/features/updates/ui/widget/updates_day_groups.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/features/updates/ui/widget/updates_refresh_error_banner.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import '../bloc/activity_offers_cubit.dart';
import 'activity_forward_row.dart';
import 'activity_offer_card.dart';
import 'activity_watching_digest_row.dart';

/// Activity redesign body: pinned offers, then activity-surface stream (§5).
class ActivityStreamView extends StatefulWidget {
  const ActivityStreamView({super.key});

  /// One bounded offer card height (UNIT 15); scroll past → held-back live arrivals.
  static const scrolledAwayThreshold = 180.0;

  @override
  State<ActivityStreamView> createState() => _ActivityStreamViewState();
}

class _ActivityStreamViewState extends State<ActivityStreamView>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  var _lastScrolledAway = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  void _onScroll() {
    _loadMoreWhenNeeded();
    if (!_scrollController.hasClients) return;
    final scrolledAway =
        _scrollController.offset > ActivityStreamView.scrolledAwayThreshold;
    if (scrolledAway == _lastScrolledAway) return;
    _lastScrolledAway = scrolledAway;
    context.read<ActivityOffersCubit>().setScrolledAway(scrolledAway);
  }

  void _loadMoreWhenNeeded() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels < position.maxScrollExtent - context.tt.sectionGap) {
      return;
    }
    final offers = context.read<ActivityOffersCubit>().state;
    if (offers.hasMore) {
      unawaited(context.read<ActivityOffersCubit>().loadMore());
      return;
    }
    unawaited(context.read<UpdatesFeedCubit>().loadNextPage());
  }

  Future<void> _refreshBoth() async {
    await Future.wait<void>([
      context.read<ActivityOffersCubit>().loadFirst(),
      context.read<UpdatesFeedCubit>().refresh(),
    ]);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ActivityOffersCubit, ActivityOffersState>(
      builder: (context, offersState) {
        return BlocBuilder<UpdatesFeedCubit, UpdatesFeedState>(
          builder: (context, streamState) {
            return _ActivityStreamScrollBody(
              scrollController: _scrollController,
              offersState: offersState,
              streamState: streamState,
              onRefresh: _refreshBoth,
            );
          },
        );
      },
    );
  }
}

class _ActivityStreamScrollBody extends StatelessWidget {
  const _ActivityStreamScrollBody({
    required this.scrollController,
    required this.offersState,
    required this.streamState,
    required this.onRefresh,
  });

  final ScrollController scrollController;
  final ActivityOffersState offersState;
  final UpdatesFeedState streamState;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final now = DateTime.now();
    final streamCubit = context.read<UpdatesFeedCubit>();
    final inboxCubit = context.read<InboxCubit>();

    final placement = computeInvitePromptPinPlacement(
      items: streamState.items,
      state: streamState,
      now: now,
    );
    final chronologicalItems = streamState.items
        .where((r) => !placement.liftedReceiptIds.contains(r.id))
        .toList(growable: false);
    final streamCells = flattenUpdatesFeed(
      items: chronologicalItems,
      hasNextPage: streamState.hasNextPage,
    );

    final slivers = <Widget>[
      SliverToBoxAdapter(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: tt.listRowPadding.left),
          child: TenturaSectionHeader(
            label: l10n.activityForYouTitle,
            count: offersState.countLoadFailed ? null : offersState.totalCount,
            semanticsIdentifier: TestIds.activityForYouHeader,
          ),
        ),
      ),
      if (offersState.pageLoadFailed)
        SliverToBoxAdapter(
          child: _ActivitySourceRetryRow(
            onRetry: () => unawaited(
              context.read<ActivityOffersCubit>().loadFirst(),
            ),
          ),
        )
      else if (offersState.isLoading && offersState.items.isEmpty)
        const SliverToBoxAdapter(
          child: Center(child: CircularProgressIndicator.adaptive()),
        )
      else ...[
        if (placement.pinnedReceipts.isNotEmpty)
          SliverList.builder(
            itemCount: placement.pinnedReceipts.length,
            itemBuilder: (context, index) {
              final receipt = placement.pinnedReceipts[index];
              return _ActivityStreamPromptPin(
                receipt: receipt,
                streamCubit: streamCubit,
              );
            },
          ),
        if (placement.collapsedCount >= 3)
          SliverToBoxAdapter(
            child: _ActivityCollapsedInvitePromptRow(
              count: placement.collapsedCount,
              onOpenBatch: () => unawaited(
                PromptBatchSheet.show(
                  context: context,
                  cubit: streamCubit,
                  receipts: placement.collapsedReceipts,
                ),
              ),
            ),
          ),
        SliverList.builder(
          itemCount: offersState.items.length,
          itemBuilder: (context, index) {
            final item = offersState.items[index];
            final showDot = offersState.unseenQueryComplete &&
                offersState.unseenBeaconIds.contains(item.beaconId);
            return KeyedSubtree(
              key: ValueKey('offer-${item.beaconId}'),
              child: ActivityOfferCard.forward(
                item: item,
                inboxCubit: inboxCubit,
                showUnseenDot: showDot,
              ),
            );
          },
        ),
        if (offersState.hasMore)
          SliverToBoxAdapter(
            child: offersState.loadingMore
                ? const _ActivityLoadMoreIndicator()
                : const SizedBox.shrink(),
          ),
      ],
      if (streamState.hasRefreshError)
        SliverToBoxAdapter(
          child: UpdatesRefreshErrorBanner(
            onRetry: () => unawaited(streamCubit.refresh()),
          ),
        ),
      SliverList.builder(
        itemCount: streamCells.length,
        itemBuilder: (context, index) {
          return _ActivityStreamCell(
            cell: streamCells[index],
            streamCubit: streamCubit,
            inboxCubit: inboxCubit,
          );
        },
      ),
    ];

    return RefreshIndicator.adaptive(
      onRefresh: onRefresh,
      child: CustomScrollView(
        controller: scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: slivers,
      ),
    );
  }
}

class _ActivityStreamPromptPin extends StatelessWidget {
  const _ActivityStreamPromptPin({
    required this.receipt,
    required this.streamCubit,
  });

  final AttentionReceipt receipt;
  final UpdatesFeedCubit streamCubit;

  @override
  Widget build(BuildContext context) {
    final subjectId = receipt.actorUserId ?? receipt.targetEntityId;
    return BlocSelector<UpdatesFeedCubit, UpdatesFeedState, PromptProjection>(
      selector: (state) => subjectId == null
          ? const PromptProjection.unknown()
          : state.promptProjectionFor(subjectId),
      builder: (context, projection) {
        return ActivityOfferCard.prompt(
          receipt: receipt,
          promptProjection: projection,
          onRetryPromptFetch: streamCubit.retryPromptFetch,
          onPromptSettled: streamCubit.applyKnownPrompt,
          onTap: () => unawaited(_open(context, receipt, streamCubit)),
          onMarkSeen: () => streamCubit.markSeen(receipt.id),
          onMarkUnseen: () => streamCubit.markUnseen(receipt.id),
        );
      },
    );
  }

  Future<void> _open(
    BuildContext context,
    AttentionReceipt receipt,
    UpdatesFeedCubit cubit,
  ) async {
    unawaited(cubit.markSeen(receipt.id));
    await GetIt.I<RootRouter>().openFromUpdate(receipt);
  }
}

class _ActivityStreamCell extends StatelessWidget {
  const _ActivityStreamCell({
    required this.cell,
    required this.streamCubit,
    required this.inboxCubit,
  });

  final UpdatesFeedCell cell;
  final UpdatesFeedCubit streamCubit;
  final InboxCubit inboxCubit;

  @override
  Widget build(BuildContext context) {
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
        return const _ActivityLoadMoreIndicator();
      case UpdatesFeedCellKind.row:
        final receipt = cell.receipt!;
        final row = _streamRow(context, receipt);
        if (!cell.showDividerBelow) return row;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [row, const TenturaHairlineDivider()],
        );
    }
  }

  Widget _streamRow(BuildContext context, AttentionReceipt receipt) {
    void onOpen() => unawaited(_openReceipt(context, receipt));
    switch (receipt.itemKind) {
      case AttentionItemKind.forward:
        final beaconId = receipt.beaconId ?? '';
        return ActivityForwardRow(
          key: ValueKey(receipt.id),
          receipt: receipt,
          onOpenBeacon: onOpen,
          onRestore: receipt.forwardOutcome ==
                  AttentionForwardOutcome.notInterested
              ? () => unawaited(inboxCubit.unreject(beaconId))
              : null,
          onHide:
              receipt.forwardOutcome == AttentionForwardOutcome.closedBeforeResponse ||
                  receipt.forwardOutcome ==
                      AttentionForwardOutcome.deletedBeforeResponse
              ? () => unawaited(streamCubit.markSeen(receipt.id))
              : null,
        );
      case AttentionItemKind.watchingDigest:
        return ActivityWatchingDigestRow(
          key: ValueKey(receipt.id),
          count: receipt.digestCount ?? 0,
        );
      case AttentionItemKind.receipt:
        return UpdatesFeedTile(
          key: ValueKey(receipt.id),
          receipt: receipt,
          onTap: onOpen,
          onMarkSeen: () => streamCubit.markSeen(receipt.id),
          onMarkUnseen: () => streamCubit.markUnseen(receipt.id),
          onSettle: receipt.isLiveObligation
              ? () => streamCubit.settle(receipt.id)
              : null,
        );
    }
  }

  Future<void> _openReceipt(
    BuildContext context,
    AttentionReceipt receipt,
  ) async {
    unawaited(streamCubit.markSeen(receipt.id));
    await GetIt.I<RootRouter>().openFromUpdate(receipt);
  }
}

class _ActivityCollapsedInvitePromptRow extends StatelessWidget {
  const _ActivityCollapsedInvitePromptRow({
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

class _ActivitySourceRetryRow extends StatelessWidget {
  const _ActivitySourceRetryRow({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tt.listRowPadding.left,
        vertical: tt.tightGap,
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined, color: tt.warn),
          SizedBox(width: tt.iconTextGap),
          Expanded(
            child: Text(
              l10n.updatesRefreshFailedBanner,
              style: TenturaText.bodySmall(tt.text),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            child: Text(l10n.myWorkRetry),
          ),
        ],
      ),
    );
  }
}

class _ActivityLoadMoreIndicator extends StatelessWidget {
  const _ActivityLoadMoreIndicator();

  @override
  Widget build(BuildContext context) => Padding(
    padding: context.tt.cardPadding,
    child: const Center(child: CircularProgressIndicator.adaptive()),
  );
}
