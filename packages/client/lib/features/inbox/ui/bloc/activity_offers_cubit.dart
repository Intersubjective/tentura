import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/activity_offer_sort_row.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';

import '../../domain/entity/inbox_item.dart';
import '../../domain/use_case/inbox_case.dart';
import 'activity_offers_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'activity_offers_state.dart';

/// Paged open forwards for the Activity pinned zone (design §5.1 / §5.6).
final class ActivityOffersCubit extends Cubit<ActivityOffersState> {
  ActivityOffersCubit({
    required String userId,
    InboxCase? inboxCase,
    AttentionCase? attentionCase,
    int pageSize = 20,
  }) : _userId = userId,
       _inboxCase = inboxCase ?? GetIt.I<InboxCase>(),
       _attention = attentionCase ?? GetIt.I<AttentionCase>(),
       _demotedController = StreamController<String>.broadcast(),
       _pageSize = pageSize,
       super(const ActivityOffersState()) {
    _deskRelevantChanges = _inboxCase.deskRelevantChanges.listen(
      _scheduleBeaconRefresh,
      cancelOnError: false,
    );
    _helpOfferChanges = _inboxCase.helpOfferChanges.listen(
      (event) => _scheduleBeaconRefresh(event.beaconId),
      cancelOnError: false,
    );
  }

  static const _deskRelevantDebounce = Duration(milliseconds: 50);
  static const _maxIdsPerRequest = 500;

  final int _pageSize;

  final String _userId;
  final InboxCase _inboxCase;
  final AttentionCase _attention;
  final StreamController<String> _demotedController;
  final _heldBackItems = <String, InboxItem>{};
  final _deskRelevantTimers = <String, Timer>{};
  final _heldBackOrder = <String>[];

  bool _scrolledAway = false;
  int _loadGeneration = 0;
  int _unseenGeneration = 0;

  late final StreamSubscription<String> _deskRelevantChanges;
  late final StreamSubscription<HelpOfferEvent> _helpOfferChanges;

  /// Emits when an open forward leaves the pinned zone (UNIT 17 motion).
  Stream<String> get demotedBeaconIds => _demotedController.stream;

  void setScrolledAway(bool scrolledAway) {
    _scrolledAway = scrolledAway;
  }

  Future<void> loadFirst() async {
    final generation = ++_loadGeneration;
    emit(
      state.copyWith(
        status: StateStatus.isLoading,
        pageLoadFailed: false,
        countLoadFailed: false,
      ),
    );

    ActivityOfferPage? offerPage;
    var pageFailed = false;
    List<InboxItem> page = const [];

    try {
      offerPage = await _attention.activityOffers(limit: _pageSize);
      page = await _hydrateInboxItems(offerPage.items);
    } catch (_) {
      pageFailed = true;
    }

    if (generation != _loadGeneration || isClosed) return;

    final resolvedPage = offerPage;
    final nextCursor = resolvedPage?.nextCursor;
    final hasMore = !pageFailed &&
        nextCursor != null &&
        nextCursor.isNotEmpty;
    emit(
      state.copyWith(
        items: pageFailed ? state.items : page,
        totalCount: pageFailed ? state.totalCount : resolvedPage?.totalCount,
        countLoadFailed: false,
        pageLoadFailed: pageFailed,
        hasMore: hasMore,
        offersNextCursor: pageFailed ? state.offersNextCursor : nextCursor,
        eventsByBeacon: pageFailed
            ? state.eventsByBeacon
            : _metaFromSortRows(resolvedPage?.items ?? const []),
        loadingMore: false,
        status: const StateIsSuccess(),
      ),
    );
    if (!pageFailed) {
      unawaited(_refreshUnseenDots());
    }
  }

  Future<void> loadMore() async {
    final cursor = state.offersNextCursor;
    if (state.loadingMore ||
        !state.hasMore ||
        cursor == null ||
        cursor.isEmpty) {
      return;
    }
    emit(state.copyWith(loadingMore: true));
    try {
      final offerPage = await _attention.activityOffers(
        cursor: cursor,
        limit: _pageSize,
      );
      final page = await _hydrateInboxItems(offerPage.items);
      if (isClosed) return;
      final existingIds = state.items.map((e) => e.beaconId).toSet();
      final merged = [
        ...state.items,
        for (final item in page)
          if (!existingIds.contains(item.beaconId)) item,
      ];
      final nextCursor = offerPage.nextCursor;
      emit(
        state.copyWith(
          items: merged,
          eventsByBeacon: {
            ...state.eventsByBeacon,
            ..._metaFromSortRows(offerPage.items),
          },
          offersNextCursor: nextCursor,
          hasMore: nextCursor != null && nextCursor.isNotEmpty,
          loadingMore: false,
        ),
      );
      unawaited(_refreshUnseenDots());
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(loadingMore: false, pageLoadFailed: true));
    }
  }

  void stageMovedToStreamNudge(String beaconId) {
    if (beaconId.isEmpty) return;
    emit(state.copyWith(pendingMovedToStreamBeaconId: beaconId));
  }

  void clearMovedToStreamNudge() {
    if (state.pendingMovedToStreamBeaconId == null) return;
    emit(state.copyWith(pendingMovedToStreamBeaconId: null));
  }

  void revealHeldBack() {
    if (state.heldBackIds.isEmpty) return;
    final ids = state.heldBackIds;
    final toReveal = [
      for (final id in _heldBackOrder)
        if (ids.contains(id)) _heldBackItems[id]!,
    ];
    final existing = [
      for (final item in state.items)
        if (!ids.contains(item.beaconId)) item,
    ];
    for (final id in ids) {
      _heldBackItems.remove(id);
    }
    _heldBackOrder.removeWhere(ids.contains);
    emit(
      state.copyWith(
        items: [...toReveal, ...existing],
        heldBackIds: const {},
      ),
    );
    unawaited(_refreshUnseenDots());
  }

  Future<void> _refreshOpenForwardsCount() async {
    try {
      final page = await _attention.activityOffers(limit: 1);
      if (isClosed) return;
      emit(
        state.copyWith(
          totalCount: page.totalCount,
          countLoadFailed: false,
        ),
      );
    } catch (_) {
      if (isClosed) return;
      emit(state.copyWith(countLoadFailed: true));
    }
  }

  void _scheduleBeaconRefresh(String beaconId) {
    if (isClosed || beaconId.isEmpty) return;
    _deskRelevantTimers.remove(beaconId)?.cancel();
    _deskRelevantTimers[beaconId] = Timer(_deskRelevantDebounce, () {
      _deskRelevantTimers.remove(beaconId);
      if (!isClosed) {
        unawaited(_refreshBeaconRow(beaconId));
      }
    });
  }

  Future<void> _refreshBeaconRow(String beaconId) async {
    InboxItem? row;
    try {
      row = await _inboxCase.fetchOpenForwardForBeacon(
        userId: _userId,
        beaconId: beaconId,
      );
    } catch (_) {
      return;
    }
    if (isClosed) return;

    if (row == null) {
      _demoteBeacon(beaconId);
    } else {
      _upsertOpenForward(row);
    }
    unawaited(_refreshOpenForwardsCount());
    unawaited(_refreshUnseenDots());
  }

  void _upsertOpenForward(InboxItem item) {
    final id = item.beaconId;
    final without = [
      for (final existing in state.items)
        if (existing.beaconId != id) existing,
    ];
    if (_scrolledAway) {
      _heldBackItems[id] = item;
      if (!_heldBackOrder.contains(id)) {
        _heldBackOrder.add(id);
      }
      emit(
        state.copyWith(
          items: without,
          heldBackIds: {...state.heldBackIds, id},
        ),
      );
      return;
    }
    _heldBackItems.remove(id);
    _heldBackOrder.remove(id);
    final heldBackIds = {...state.heldBackIds}..remove(id);
    emit(
      state.copyWith(
        items: [item, ...without],
        heldBackIds: heldBackIds,
      ),
    );
  }

  void _demoteBeacon(String beaconId) {
    final hadItem =
        state.items.any((e) => e.beaconId == beaconId) ||
        state.heldBackIds.contains(beaconId);
    _heldBackItems.remove(beaconId);
    _heldBackOrder.remove(beaconId);
    final eventsByBeacon = Map<String, ActivityOfferBeaconMeta>.from(
      state.eventsByBeacon,
    )..remove(beaconId);
    emit(
      state.copyWith(
        items: [
          for (final item in state.items)
            if (item.beaconId != beaconId) item,
        ],
        heldBackIds: {...state.heldBackIds}..remove(beaconId),
        eventsByBeacon: eventsByBeacon,
      ),
    );
    if (hadItem && !_demotedController.isClosed) {
      _demotedController.add(beaconId);
    }
  }

  Future<void> _refreshUnseenDots() async {
    final generation = ++_unseenGeneration;
    final beaconIds = state.items.map((e) => e.beaconId).toList(growable: false);
    if (beaconIds.isEmpty) {
      emit(
        state.copyWith(
          unseenBeaconIds: const {},
          unseenQueryComplete: true,
        ),
      );
      return;
    }
    final fromMeta = {
      for (final id in beaconIds)
        if (state.eventsByBeacon[id]?.unseen == true) id,
    };
    if (fromMeta.length == beaconIds.length) {
      emit(
        state.copyWith(
          unseenBeaconIds: fromMeta,
          unseenQueryComplete: true,
        ),
      );
      return;
    }
    try {
      final unread = <String>{...fromMeta};
      for (var offset = 0; offset < beaconIds.length; offset += _maxIdsPerRequest) {
        final nextOffset = offset + _maxIdsPerRequest;
        final end = nextOffset < beaconIds.length ? nextOffset : beaconIds.length;
        unread.addAll(
          await _attention.unreadForBeacons(
            beaconIds.sublist(offset, end).toSet(),
          ),
        );
      }
      if (isClosed || generation != _unseenGeneration) return;
      emit(
        state.copyWith(
          unseenBeaconIds: unread.intersection(beaconIds.toSet()),
          unseenQueryComplete: true,
        ),
      );
    } catch (_) {
      if (isClosed || generation != _unseenGeneration) return;
      emit(state.copyWith(unseenQueryComplete: false));
    }
  }

  Future<List<InboxItem>> _hydrateInboxItems(
    List<ActivityOfferSortRow> rows,
  ) async {
    if (rows.isEmpty) return const [];
    final ids = rows.map((e) => e.beaconId).toList(growable: false);
    final hydrated = await _inboxCase.fetchInboxItemsForBeacons(
      userId: _userId,
      beaconIds: ids,
    );
    final byId = {for (final item in hydrated) item.beaconId: item};
    return [
      for (final id in ids)
        if (byId.containsKey(id)) byId[id]!,
    ];
  }

  Map<String, ActivityOfferBeaconMeta> _metaFromSortRows(
    List<ActivityOfferSortRow> rows,
  ) => {
    for (final row in rows)
      row.beaconId: ActivityOfferBeaconMeta(
        eventTotal: row.eventTotal,
        eventUnseenCount: row.eventUnseenCount,
        eventsPreview: row.eventsPreview,
        unseen: row.unseen,
      ),
  };

  @override
  Future<void> close() async {
    for (final timer in _deskRelevantTimers.values) {
      timer.cancel();
    }
    _deskRelevantTimers.clear();
    await _deskRelevantChanges.cancel();
    await _helpOfferChanges.cancel();
    await _demotedController.close();
    return super.close();
  }
}
