import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/components/tentura_attention_summary_row.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/attention/for_you_stream_entries.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/updates/domain/entity/prompt_projection.dart';
import 'package:tentura/features/updates/ui/bloc/updates_feed_cubit.dart';
import 'package:tentura/features/updates/ui/widget/invite_accepted_receipt_card.dart';
import 'package:tentura/features/updates/ui/widget/prompt_batch_sheet.dart';
import 'package:tentura/features/updates/ui/widget/updates_day_groups.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_pane.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/features/updates/ui/widget/updates_refresh_error_banner.dart';
import 'package:tentura/features/attention/ui/widget/request_attention_timeline_sheet.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../domain/entity/inbox_item.dart';
import '../bloc/activity_offers_cubit.dart';
import '../../domain/entity/inbox_provenance.dart';
import 'inbox_card_actions.dart';
import 'rejection_dialog.dart';
import 'request_attention_card.dart';
import 'request_attention_card_mapper.dart';
import 'tombstone_row.dart';
import 'for_you_empty_state.dart';

/// Activity redesign body: pinned offers, then activity-surface stream (§5).
class ActivityStreamView extends StatefulWidget {
  const ActivityStreamView({this.scrollController, super.key});

  final ScrollController? scrollController;

  /// One bounded offer card height (UNIT 15); scroll past → held-back live arrivals.
  static const scrolledAwayThreshold = 180.0;

  static const demotionMotionDuration = Duration(milliseconds: 225);

  @override
  State<ActivityStreamView> createState() => _ActivityStreamViewState();
}

class _ActivityStreamViewState extends State<ActivityStreamView>
    with WidgetsBindingObserver {
  late final ScrollController _scrollController;
  var _ownsScrollController = false;
  final _offerSnapshot = <String, InboxItem>{};
  final _exitingOffers = <String, InboxItem>{};
  final _enteringForwardBeacons = <String>{};
  final _forwardRowKeys = <String, GlobalKey>{};

  var _lastScrolledAway = false;
  StreamSubscription<String>? _demotedSub;

  @override
  void initState() {
    super.initState();
    if (widget.scrollController != null) {
      _scrollController = widget.scrollController!;
    } else {
      _scrollController = ScrollController();
      _ownsScrollController = true;
    }
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
    _scrollController.removeListener(_onScroll);
    if (_ownsScrollController) {
      _scrollController.dispose();
    }
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
    // One representative per Request (§6). The pinned zone is a Request's
    // representative while it is in it — including while it is animating out,
    // or a demoted Request would briefly wear two surfaces at once.
    final entries = forYouStreamEntries(
      receipts: chronologicalItems,
      pinnedBeaconIds: {
        for (final item in offersState.items) item.beaconId,
        ...exitingOffers.keys,
      },
    );
    final entryByReceiptId = {
      for (final entry in entries) entry.receipt.id: entry,
    };
    final streamCells = flattenUpdatesFeed(
      items: [for (final entry in entries) entry.receipt],
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
                child: _PinnedRequestCard(
                  item: item,
                  inboxCubit: inboxCubit,
                  showUnseenDot: showDot,
                  eventsMeta: offersState.eventsByBeacon[item.beaconId],
                  actors: offersState.actors,
                ),
              );
            }
            final exitEntry =
                exitingOffers.entries.elementAt(index - offersState.items.length);
            final beaconId = exitEntry.key;
            final item = exitEntry.value;
            final showDot = offersState.unseenQueryComplete &&
                offersState.unseenBeaconIds.contains(beaconId);
            final card = _PinnedRequestCard(
              item: item,
              inboxCubit: inboxCubit,
              showUnseenDot: showDot,
              eventsMeta: offersState.eventsByBeacon[beaconId],
              actors: offersState.actors,
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
      // U16c-1 / §4 — the empty stream, in one of three voices. It is **not**
      // rendered while the surface is still loading or has failed to refresh:
      // §4's _Avoid_ line forbids celebrating a clear surface while loading or
      // offline, and a spinner replaced by "nothing new" is exactly that.
      if (shouldShowForYouEmptyState(
        hasRows: streamCells.isNotEmpty,
        isLoading: streamState.isLoading || offersState.isLoading,
        hasError: streamState.hasRefreshError || offersState.pageLoadFailed,
      ))
        SliverToBoxAdapter(
          // D18 — the cleared state rewards the completion, and after an
          // explicit sweep it states the number that sweep actually cleared.
          // The sweep runs from the app bar, outside this subtree, so the
          // attention owner is what carries its result here.
          child: StreamBuilder<AttentionDismissAllResult?>(
            stream: GetIt.I<AttentionCase>().lastSweepOutcome,
            builder: (context, snapshot) => ForYouEmptyState(
              kind: forYouEmptyKind(
                // For You carries no filter control today; the state exists
                // because §4 names three, and it is wired here rather than
                // inlined so a filter gains its copy by passing `true`.
                hasActiveFilter: false,
                hasPinnedZone: placement.pinnedReceipts.isNotEmpty ||
                    offersState.items.isNotEmpty,
                wasClearedHere: forYouSweptHere(snapshot.data),
              ),
              lastSweep: snapshot.data,
            ),
          ),
        ),
      SliverList.builder(
        itemCount: streamCells.length,
        itemBuilder: (context, index) {
          return _ActivityStreamCell(
            cell: streamCells[index],
            entryByReceiptId: entryByReceiptId,
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

/// The pinned zone's Request, as the card's `pinned` variant (§9).
///
/// Its action row is the whole point — «Предложить помощь», «Переслать»,
/// «Следить» — and it deliberately carries **no** × (E17): «Не могу помочь»
/// is a social act, lives in the overflow menu and opens the rejection
/// dialog, so it is never worn as the quiet private gesture.
class _PinnedRequestCard extends StatelessWidget {
  const _PinnedRequestCard({
    required this.item,
    required this.inboxCubit,
    required this.showUnseenDot,
    this.eventsMeta,
    this.actors = const {},
  });

  final InboxItem item;
  final InboxCubit inboxCubit;
  final bool showUnseenDot;
  final ActivityOfferBeaconMeta? eventsMeta;
  final Map<String, Profile> actors;

  @override
  Widget build(BuildContext context) {
    final model = requestCardFromInboxItem(item, meta: eventsMeta);
    if (model == null) return const SizedBox.shrink();
    final beaconId = item.beaconId;

    // §4 — nothing clears before navigation. The detail host clears the
    // snapshot once the Request has actually displayed.
    Future<void> openBeacon() async {
      await context.router.push(
        BeaconViewRoute(id: beaconId, entry: kBeaconEntryInbox),
      );
    }

    Future<void> cantHelp() async {
      final message = await showInboxDismissDialog(context);
      if (!context.mounted || message == null) return;
      await inboxCubit.reject(beaconId, message: message);
    }

    return Semantics(
      identifier: TestIds.activityOffer(beaconId),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: context.tt.listRowPadding.left,
          vertical: context.tt.tightGap,
        ),
        child: RequestAttentionCard(
          beacon: model.beacon,
          facts: model.facts,
          variant: model.variant,
          provenance: model.provenance,
          eventTotal: model.eventTotal,
          eventsPreview: model.eventsPreview,
          actors: actors,
          onOpenBeacon: () => unawaited(openBeacon()),
          onOpenTimeline: () => unawaited(
            showRequestAttentionTimelineSheet(context, beaconId: beaconId),
          ),
          onOfferHelp: () =>
              unawaited(inboxOfferHelp(context, model.beacon)),
          onForward: model.allowsForward
              ? () => unawaited(inboxForwardItem(context, item))
              : null,
          onFollow: () => unawaited(inboxCubit.setWatching(beaconId)),
          onCantHelp: cantHelp,
        ),
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
        // CHANGES IN U16c-2: `ActivityOfferCard.prompt` was a thin wrapper
        // over this card inside the bounded offer shell; the wrapper is gone,
        // the pin key and the shell flag stay exactly where they were.
        return KeyedSubtree(
          key: TestIds.key(TestIds.activityPromptPin(receipt.id)),
          child: InviteAcceptedReceiptCard(
            receipt: receipt,
            promptProjection: projection,
            onRetryPromptFetch: streamCubit.retryPromptFetch,
            onPromptSettled: streamCubit.applyKnownPrompt,
            onTap: () => unawaited(_open(context, receipt, streamCubit)),
            onMarkSeen: () => streamCubit.markSeen(receipt.id),
            onMarkUnseen: () => streamCubit.markUnseen(receipt.id),
            activityOfferBoundedShell: true,
          ),
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
    required this.entryByReceiptId,
    required this.streamCubit,
    required this.inboxCubit,
    required this.enteringForwardBeacons,
    required this.onForwardRevealComplete,
    required this.forwardRowKeyFor,
    required this.animateMotion,
  });

  final UpdatesFeedCell cell;
  final Map<String, ForYouStreamEntry> entryByReceiptId;
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
    Future<void> onOpenParent() async {
      final beaconId = receipt.beaconId;
      if (beaconId == null || beaconId.isEmpty) {
        // No Request behind this row, so no detail host will clear it: the
        // read axis is all there is (§3).
        unawaited(streamCubit.markSeen(receipt.id));
      }
      if (!context.mounted) return;
      await GetIt.I<RootRouter>().openFromUpdate(receipt);
    }

    final entry = entryByReceiptId[receipt.id];
    final beaconId = receipt.beaconId ?? '';

    switch (entry?.kind ?? ForYouStreamEntryKind.tile) {
      // §8 — a memory of an act, with the private ×. Every outcome kind has
      // one (A1, m0183), not only the two before-response terminals.
      case ForYouStreamEntryKind.tombstone:
        final row = Semantics(
          identifier: TestIds.activityForwardRow(beaconId),
          // The demotion scroll addresses the row by this identifier and by
          // `forwardRowKeyFor`; both survive the change of widget.
          child: TombstoneRow(
            key: ValueKey(receipt.id),
            receipt: receipt,
            forwarder: _forwarderOf(receipt),
            onOpenBeacon: () => unawaited(onOpenParent()),
            onDismiss: () {
              // Durable on the server (`inbox_item.tombstone_dismissed_at`),
              // and gone from the list this frame: the feed's optimistic ack
              // drops an outcome row, whose unread-view membership is
              // `false` for every kind.
              unawaited(inboxCubit.dismissTombstone(beaconId));
              unawaited(streamCubit.markSeen(receipt.id));
            },
            onRestore:
                receipt.forwardOutcome ==
                    AttentionForwardOutcome.notInterested
                ? () => unawaited(inboxCubit.unreject(beaconId))
                : null,
          ),
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

      // §6 — one card for the Request, its events as mini-cards inside it
      // under the `timeline` policy (D-171-5b). No tile, no sibling block.
      case ForYouStreamEntryKind.card:
        final model = requestCardFromReceipt(
          receipt,
          relation: entry?.relation ?? ForYouStreamRelation.none,
        );
        if (model == null) return _feedTile(context, receipt, onOpenParent);
        final card = Padding(
          padding: EdgeInsets.symmetric(
            horizontal: context.tt.listRowPadding.left,
            vertical: context.tt.tightGap,
          ),
          child: RequestAttentionCard(
            key: ValueKey(receipt.id),
            beacon: model.beacon,
            facts: model.facts,
            variant: model.variant,
            relation: model.relation,
            provenance: model.provenance,
            representative: model.representative,
            eventTotal: model.eventTotal,
            eventsPreview: model.eventsPreview,
            actors: streamCubit.state.actors,
            onOpenBeacon: () => unawaited(onOpenParent()),
            onOpenTimeline: () => unawaited(
              showRequestAttentionTimelineSheet(context, beaconId: beaconId),
            ),
            onClearEvent: (id) => unawaited(
              GetIt.I<AttentionCase>().clearReceipt(receiptId: id),
            ),
            onClearAll: beaconId.isEmpty
                ? null
                : () => unawaited(
                    GetIt.I<AttentionCase>().clearBeacon(beaconId: beaconId),
                  ),
          ),
        );
        return KeyedSubtree(key: forwardRowKeyFor(beaconId), child: card);

      case ForYouStreamEntryKind.tile:
        return _feedTile(context, receipt, onOpenParent);
    }
  }

  /// An ungrouped receipt — not about a Request, so not a card.
  Widget _feedTile(
    BuildContext context,
    AttentionReceipt receipt,
    Future<void> Function() onOpenParent,
  ) {
    final actorId = receipt.actorUserId?.trim() ?? '';
    final actor = actorId.isEmpty ? null : streamCubit.state.actors[actorId];
    return UpdatesFeedTile(
      key: ValueKey(receipt.id),
      receipt: receipt,
      actor: actor,
      onTap: () => unawaited(onOpenParent()),
      onMarkSeen: () => streamCubit.markSeen(receipt.id),
      onMarkUnseen: () => streamCubit.markUnseen(receipt.id),
      onSettle: receipt.isUserSettleable
          ? () => streamCubit.settle(receipt.id)
          : null,
    );
  }

  /// §8 — the last forwarder leads the row. The old paper-plane glyph is a
  /// *send* affordance and misread as "I sent this". The server writes no
  /// `actor_user_id` on an outcome row, so the forwarder comes from the
  /// Request's provenance, resolved through the feed's actor profiles.
  Profile? _forwarderOf(AttentionReceipt receipt) {
    final provenance = InboxProvenance.parse(receipt.provenanceJson);
    final senderId =
        provenance.latestNoteForward?.senderId ??
        (provenance.senders.isEmpty ? null : provenance.senders.first.id);
    if (senderId == null || senderId.isEmpty) return null;
    return streamCubit.state.actors[senderId] ??
        Profile(
          id: senderId,
          displayName:
              provenance.latestNoteForward?.displayName ??
              provenance.senders.first.displayName,
        );
  }

  Future<void> _openReceipt(
    BuildContext context,
    AttentionReceipt receipt,
  ) async {
    final beaconId = receipt.beaconId;
    if (beaconId == null || beaconId.isEmpty) {
      unawaited(streamCubit.markSeen(receipt.id));
    }
    if (!context.mounted) return;
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
