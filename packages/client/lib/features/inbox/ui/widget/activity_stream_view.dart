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
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/entity/inbox_item.dart';
import '../bloc/activity_offers_cubit.dart';
import 'activity_forward_row.dart';
import 'activity_offer_card.dart';
import 'activity_watching_digest_row.dart';

/// Activity redesign body: pinned offers, then activity-surface stream (§5).
class ActivityStreamView extends StatefulWidget {
  const ActivityStreamView({super.key});

  /// One bounded offer card height (UNIT 15); scroll past → held-back live arrivals.
  static const scrolledAwayThreshold = 180.0;

  static const demotionMotionDuration = Duration(milliseconds: 225);

  @override
  State<ActivityStreamView> createState() => _ActivityStreamViewState();
}

class _ActivityStreamViewState extends State<ActivityStreamView>
    with WidgetsBindingObserver {
  final _scrollController = ScrollController();
  final _offerSnapshot = <String, InboxItem>{};
  final _exitingOffers = <String, InboxItem>{};
  final _enteringForwardBeacons = <String>{};
  final _forwardRowKeys = <String, GlobalKey>{};

  var _lastScrolledAway = false;
  StreamSubscription<String>? _demotedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _demotedSub = context
          .read<ActivityOffersCubit>()
          .demotedBeaconIds
          .listen(_onDemotedBeacon);
      _syncScrollAwayFromOffset();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    }
  }

  void _syncScrollAwayFromOffset() {
    if (!_scrollController.hasClients) return;
    final scrolledAway =
        _scrollController.offset > ActivityStreamView.scrolledAwayThreshold;
    _lastScrolledAway = scrolledAway;
    context.read<ActivityOffersCubit>().setScrolledAway(scrolledAway);
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

  void _rememberOffers(ActivityOffersState offersState) {
    for (final item in offersState.items) {
      _offerSnapshot[item.beaconId] = item;
    }
  }

  void _onDemotedBeacon(String beaconId) {
    final item = _offerSnapshot[beaconId];
    if (item != null) {
      setState(() => _exitingOffers[beaconId] = item);
      final animate = !MediaQuery.disableAnimationsOf(context);
      if (!animate) {
        _finishPinnedExit(beaconId);
      }
    }
    unawaited(_refreshStreamAfterDemotion(beaconId));
  }

  Future<void> _refreshStreamAfterDemotion(String beaconId) async {
    final streamCubit = context.read<UpdatesFeedCubit>();
    await streamCubit.refresh();
    if (!mounted) return;
    await _resolveDemotedForwardPlacement(beaconId);
  }

  void _finishPinnedExit(String beaconId) {
    if (!_exitingOffers.containsKey(beaconId)) return;
    setState(() => _exitingOffers.remove(beaconId));
  }

  void _finishForwardReveal(String beaconId) {
    if (!_enteringForwardBeacons.contains(beaconId)) return;
    setState(() => _enteringForwardBeacons.remove(beaconId));
  }

  AttentionReceipt? _forwardReceiptForBeacon(
    UpdatesFeedState streamState,
    String beaconId,
  ) {
    for (final receipt in streamState.items) {
      if (receipt.itemKind != AttentionItemKind.forward) continue;
      if (receipt.beaconId == beaconId) return receipt;
    }
    return null;
  }

  bool _isForwardRowInViewport(String beaconId) {
    final key = _forwardRowKeys[beaconId];
    final rowContext = key?.currentContext;
    if (rowContext == null) return false;
    final renderObject = rowContext.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) return false;

    final scrollContext = _scrollController.position.context.storageContext;
    final scrollBox = scrollContext.findRenderObject();
    if (scrollBox is! RenderBox || !scrollBox.hasSize) return false;

    final rowTop = renderObject.localToGlobal(Offset.zero).dy;
    final rowBottom = rowTop + renderObject.size.height;
    final viewTop = scrollBox.localToGlobal(Offset.zero).dy;
    final viewBottom = viewTop + scrollBox.size.height;
    return rowBottom > viewTop && rowTop < viewBottom;
  }

  Future<void> _resolveDemotedForwardPlacement(String beaconId) async {
    final streamCubit = context.read<UpdatesFeedCubit>();
    final offersCubit = context.read<ActivityOffersCubit>();

    for (var pass = 0; pass < 40 && mounted; pass++) {
      final receipt = _forwardReceiptForBeacon(streamCubit.state, beaconId);
      if (receipt == null) {
        if (!streamCubit.state.hasNextPage) break;
        await streamCubit.loadNextPage();
        await _waitForLayout();
        continue;
      }

      await _waitForLayout();
      if (!mounted) return;
      if (_isForwardRowInViewport(beaconId)) {
        final animate = !MediaQuery.disableAnimationsOf(context);
        if (animate) {
          setState(() => _enteringForwardBeacons.add(beaconId));
        }
        return;
      }
      offersCubit.stageMovedToStreamNudge(beaconId);
      return;
    }

    if (mounted && _forwardReceiptForBeacon(streamCubit.state, beaconId) != null) {
      offersCubit.stageMovedToStreamNudge(beaconId);
    }
  }

  Future<void> _waitForLayout() async {
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _scrollToForwardBeacon(String beaconId) async {
    final streamCubit = context.read<UpdatesFeedCubit>();
    for (var pass = 0; pass < 40 && mounted; pass++) {
      await _waitForLayout();
      final key = _forwardRowKeys[beaconId];
      final rowContext = key?.currentContext;
      if (rowContext != null) {
        await Scrollable.ensureVisible(
          rowContext,
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 300),
          alignment: 0.1,
        );
        return;
      }
      if (_forwardReceiptForBeacon(streamCubit.state, beaconId) == null &&
          streamCubit.state.hasNextPage) {
        await streamCubit.loadNextPage();
        continue;
      }
      if (_forwardReceiptForBeacon(streamCubit.state, beaconId) != null) {
        await _waitForLayout();
        final retryContext = _forwardRowKeys[beaconId]?.currentContext;
        if (retryContext != null) {
          await Scrollable.ensureVisible(
            retryContext,
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 300),
            alignment: 0.1,
          );
          return;
        }
        if (_scrollController.hasClients) {
          final position = _scrollController.position;
          if (position.pixels < position.maxScrollExtent) {
            final stepTarget = (position.pixels + position.viewportDimension * 0.85)
                .clamp(0.0, position.maxScrollExtent);
            if (MediaQuery.disableAnimationsOf(context)) {
              _scrollController.jumpTo(stepTarget);
            } else {
              await _scrollController.animateTo(
                stepTarget,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
            continue;
          }
          // Lazy stream rows may still be unbuilt at max extent; nudge once more.
          if (_forwardRowKeys[beaconId]?.currentContext == null &&
              position.maxScrollExtent > 0) {
            if (MediaQuery.disableAnimationsOf(context)) {
              _scrollController.jumpTo(position.maxScrollExtent);
            } else {
              await _scrollController.animateTo(
                position.maxScrollExtent,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
              );
            }
            continue;
          }
        }
        return;
      }
      break;
    }
  }

  void _onNewItemsPillTap() {
    unawaited(
      _scrollController.animateTo(
        0,
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      ),
    );
    context.read<ActivityOffersCubit>().revealHeldBack();
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

  GlobalKey _forwardRowKey(String beaconId) =>
      _forwardRowKeys.putIfAbsent(beaconId, GlobalKey.new);

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_demotedSub?.cancel());
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ActivityOffersCubit, ActivityOffersState>(
      listenWhen: (previous, current) =>
          current.pendingMovedToStreamBeaconId != null &&
          previous.pendingMovedToStreamBeaconId !=
              current.pendingMovedToStreamBeaconId,
      listener: (context, state) {
        final beaconId = state.pendingMovedToStreamBeaconId;
        if (beaconId == null) return;
        final l10n = L10n.of(context)!;
        showSnackBar(
          context,
          text: l10n.activityMovedToStream,
          action: SnackBarAction(
            label: l10n.activityShowInStream,
            onPressed: () => unawaited(_scrollToForwardBeacon(beaconId)),
          ),
        );
        context.read<ActivityOffersCubit>().clearMovedToStreamNudge();
      },
      child: BlocBuilder<ActivityOffersCubit, ActivityOffersState>(
        builder: (context, offersState) {
          _rememberOffers(offersState);
          return BlocBuilder<UpdatesFeedCubit, UpdatesFeedState>(
            builder: (context, streamState) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  _ActivityStreamScrollBody(
                    scrollController: _scrollController,
                    offersState: offersState,
                    streamState: streamState,
                    onRefresh: _refreshBoth,
                    exitingOffers: _exitingOffers,
                    onPinnedExitComplete: _finishPinnedExit,
                    enteringForwardBeacons: _enteringForwardBeacons,
                    onForwardRevealComplete: _finishForwardReveal,
                    forwardRowKeyFor: _forwardRowKey,
                  ),
                  if (offersState.heldBackIds.isNotEmpty)
                    _ActivityNewItemsPill(
                      count: offersState.heldBackIds.length,
                      onTap: _onNewItemsPillTap,
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ActivityNewItemsPill extends StatelessWidget {
  const _ActivityNewItemsPill({
    required this.count,
    required this.onTap,
  });

  final int count;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;

    return Positioned(
      top: tt.tightGap,
      left: tt.listRowPadding.left,
      right: tt.listRowPadding.right,
      child: Center(
        child: Material(
          color: scheme.primaryContainer,
          elevation: 2,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(tt.cardRadius),
            child: Semantics(
              identifier: TestIds.activityNewItemsPill,
              button: true,
              label: l10n.activityNewItemsPill(count),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tt.rowGap,
                  vertical: tt.tightGap,
                ),
                child: Text(
                  l10n.activityNewItemsPill(count),
                  style: TenturaText.labelLarge(scheme.onPrimaryContainer),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ActivityStreamScrollBody extends StatelessWidget {
  const _ActivityStreamScrollBody({
    required this.scrollController,
    required this.offersState,
    required this.streamState,
    required this.onRefresh,
    required this.exitingOffers,
    required this.onPinnedExitComplete,
    required this.enteringForwardBeacons,
    required this.onForwardRevealComplete,
    required this.forwardRowKeyFor,
  });

  final ScrollController scrollController;
  final ActivityOffersState offersState;
  final UpdatesFeedState streamState;
  final Future<void> Function() onRefresh;
  final Map<String, InboxItem> exitingOffers;
  final void Function(String beaconId) onPinnedExitComplete;
  final Set<String> enteringForwardBeacons;
  final void Function(String beaconId) onForwardRevealComplete;
  final GlobalKey Function(String beaconId) forwardRowKeyFor;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final now = DateTime.now();
    final streamCubit = context.read<UpdatesFeedCubit>();
    final inboxCubit = context.read<InboxCubit>();
    final animateMotion = !MediaQuery.disableAnimationsOf(context);

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
          itemCount: offersState.items.length + exitingOffers.length,
          itemBuilder: (context, index) {
            if (index < offersState.items.length) {
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
            }
            final exitEntry =
                exitingOffers.entries.elementAt(index - offersState.items.length);
            final beaconId = exitEntry.key;
            final item = exitEntry.value;
            final showDot = offersState.unseenQueryComplete &&
                offersState.unseenBeaconIds.contains(beaconId);
            final card = ActivityOfferCard.forward(
              item: item,
              inboxCubit: inboxCubit,
              showUnseenDot: showDot,
            );
            return KeyedSubtree(
              key: ValueKey('offer-exit-$beaconId'),
              child: _ActivitySizeFadeCollapse(
                animate: animateMotion,
                onComplete: () => onPinnedExitComplete(beaconId),
                child: card,
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
            enteringForwardBeacons: enteringForwardBeacons,
            onForwardRevealComplete: onForwardRevealComplete,
            forwardRowKeyFor: forwardRowKeyFor,
            animateMotion: animateMotion,
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

class _ActivitySizeFadeCollapse extends StatefulWidget {
  const _ActivitySizeFadeCollapse({
    required this.animate,
    required this.onComplete,
    required this.child,
  });

  final bool animate;
  final VoidCallback onComplete;
  final Widget child;

  @override
  State<_ActivitySizeFadeCollapse> createState() =>
      _ActivitySizeFadeCollapseState();
}

class _ActivitySizeFadeCollapseState extends State<_ActivitySizeFadeCollapse>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ActivityStreamView.demotionMotionDuration,
    );
    if (!widget.animate) {
      _complete();
      return;
    }
    unawaited(
      _controller.forward().then((_) {
        if (mounted) _complete();
      }),
    );
  }

  void _complete() {
    if (_completed) return;
    _completed = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return const SizedBox.shrink();
    }
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: Tween<double>(begin: 1, end: 0).animate(animation),
        child: widget.child,
      ),
    );
  }
}

class _ActivitySizeFadeReveal extends StatefulWidget {
  const _ActivitySizeFadeReveal({
    required this.animate,
    required this.onComplete,
    required this.child,
  });

  final bool animate;
  final VoidCallback onComplete;
  final Widget child;

  @override
  State<_ActivitySizeFadeReveal> createState() => _ActivitySizeFadeRevealState();
}

class _ActivitySizeFadeRevealState extends State<_ActivitySizeFadeReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  var _completed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: ActivityStreamView.demotionMotionDuration,
    );
    if (!widget.animate) {
      _complete();
      return;
    }
    _controller.value = 0;
    unawaited(
      _controller.forward().then((_) {
        if (mounted) _complete();
      }),
    );
  }

  void _complete() {
    if (_completed) return;
    _completed = true;
    widget.onComplete();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate) {
      return widget.child;
    }
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    );
    return SizeTransition(
      sizeFactor: animation,
      axisAlignment: -1,
      child: FadeTransition(
        opacity: Tween<double>(begin: 0, end: 1).animate(animation),
        child: widget.child,
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
    required this.enteringForwardBeacons,
    required this.onForwardRevealComplete,
    required this.forwardRowKeyFor,
    required this.animateMotion,
  });

  final UpdatesFeedCell cell;
  final UpdatesFeedCubit streamCubit;
  final InboxCubit inboxCubit;
  final Set<String> enteringForwardBeacons;
  final void Function(String beaconId) onForwardRevealComplete;
  final GlobalKey Function(String beaconId) forwardRowKeyFor;
  final bool animateMotion;

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
        final row = ActivityForwardRow(
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
        final keyed = KeyedSubtree(
          key: forwardRowKeyFor(beaconId),
          child: row,
        );
        if (!enteringForwardBeacons.contains(beaconId)) {
          return keyed;
        }
        return _ActivitySizeFadeReveal(
          animate: animateMotion,
          onComplete: () => onForwardRevealComplete(beaconId),
          child: keyed,
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
