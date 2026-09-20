import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/domain/attention/entity/attention_clear.dart';
import 'package:tentura/domain/attention/entity/my_work_beacon_attention.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/block/domain/use_case/block_case.dart';

import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';

import 'my_work_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'my_work_state.dart';

class MyWorkCubit extends Cubit<MyWorkState> {
  MyWorkCubit({
    required this._userId,
    MyWorkCase? myWorkCase,
    RealtimeSyncCase? realtimeSyncCase,
    BlockCase? blockCase,
  }) : _myWorkCase = myWorkCase ?? GetIt.I<MyWorkCase>(),
       super(const MyWorkState()) {
    _beaconChanges = _myWorkCase.beaconChanges.listen(
      _onBeaconChanged,
      cancelOnError: false,
    );
    _helpOfferChanges = _myWorkCase.helpOfferChanges.listen(
      (_) => unawaited(fetch(showLoading: false)),
      cancelOnError: false,
    );
    _reviewPackageChanges = _myWorkCase.reviewPackageChanges.listen(
      (_) => unawaited(fetch(showLoading: false)),
      cancelOnError: false,
    );
    _forwardChanges = _myWorkCase.forwardChanges.listen(
      (_) => unawaited(fetch(showLoading: false)),
      cancelOnError: false,
    );
    _readWatermarkSub = _myWorkCase.readWatermarkChanges.listen(
      (_) => unawaited(fetch(showLoading: false)),
      cancelOnError: false,
    );
    _deskRelevantChanges = _myWorkCase.deskRelevantInvalidations.listen(
      _onDeskRelevantInvalidation,
      cancelOnError: false,
    );
    // U13c published these for projection owners and had none. My Desk is
    // one: a Request that changes surface or gains state has to be re-read
    // here, or the desk keeps showing work that is no longer the viewer's.
    _requestInvalidations = _myWorkCase.requestInvalidations.listen(
      _onRequestInvalidated,
      cancelOnError: false,
    );
    _bookkeepingRefresh = _myWorkCase.bookkeepingRefresh.listen(
      (_) => unawaited(fetch(showLoading: false)),
      cancelOnError: false,
    );
    _catchUps = _myWorkCase.catchUps.listen(
      (_) => _scheduleCatchUp(),
      cancelOnError: false,
    );
    final realtime =
        realtimeSyncCase ??
        (GetIt.I.isRegistered<RealtimeSyncCase>()
            ? GetIt.I<RealtimeSyncCase>()
            : null);
    if (realtime != null) {
      _obligationNotificationChanges = realtime
          .changesFor(const {RealtimeEntityKind.notification})
          .listen(
            (_) => unawaited(fetch(showLoading: false)),
            cancelOnError: false,
          );
    }
    final block =
        blockCase ??
        (GetIt.I.isRegistered<BlockCase>() ? GetIt.I<BlockCase>() : null);
    if (block != null) {
      _blockChanges = block.changes.listen(
        (_) => unawaited(fetch(showLoading: false)),
        cancelOnError: false,
      );
    }
    unawaited(fetch());
  }

  static const _pendingRetryDelay = Duration(milliseconds: 400);
  static const _deskRelevantDebounce = Duration(milliseconds: 100);
  static const _catchUpDebounce = Duration(milliseconds: 100);
  static const _roomMessageHintRetryDelay = Duration(milliseconds: 300);

  final String _userId;
  final MyWorkCase _myWorkCase;

  /// Incremented on every [fetch]; stale async completions must not emit.
  int _fetchSeq = 0;

  /// Authored desk cards from repository events not yet confirmed by desk init.
  final _pendingDeskBeaconIds = <String>{};

  Timer? _pendingRetryTimer;
  Timer? _catchUpTimer;

  final _invalidationTimers = <String, Timer>{};
  final _deskRelevantTimers = <String, Timer>{};
  final _roomMessageHintRetryTimers = <String, Timer>{};

  bool _fetchInFlight = false;
  bool _fetchQueued = false;

  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChanges;

  late final StreamSubscription<dynamic> _helpOfferChanges;
  late final StreamSubscription<void> _reviewPackageChanges;

  late final StreamSubscription<String> _forwardChanges;

  late final StreamSubscription<String> _readWatermarkSub;

  late final StreamSubscription<BeaconRoomInvalidation> _deskRelevantChanges;

  late final StreamSubscription<String> _requestInvalidations;
  late final StreamSubscription<void> _bookkeepingRefresh;
  late final StreamSubscription<void> _catchUps;
  StreamSubscription<RealtimeEntityChange>? _obligationNotificationChanges;
  StreamSubscription<dynamic>? _blockChanges;

  @override
  Future<void> close() async {
    _pendingRetryTimer?.cancel();
    _catchUpTimer?.cancel();
    for (final timer in _deskRelevantTimers.values) {
      timer.cancel();
    }
    _deskRelevantTimers.clear();
    for (final timer in _roomMessageHintRetryTimers.values) {
      timer.cancel();
    }
    _roomMessageHintRetryTimers.clear();
    for (final timer in _invalidationTimers.values) {
      timer.cancel();
    }
    _invalidationTimers.clear();
    await _beaconChanges.cancel();
    await _helpOfferChanges.cancel();
    await _reviewPackageChanges.cancel();
    await _forwardChanges.cancel();
    await _readWatermarkSub.cancel();
    await _deskRelevantChanges.cancel();
    await _requestInvalidations.cancel();
    await _bookkeepingRefresh.cancel();
    await _catchUps.cancel();
    await _obligationNotificationChanges?.cancel();
    await _blockChanges?.cancel();
    return super.close();
  }

  void _scheduleCatchUp() {
    if (isClosed) return;
    _catchUpTimer?.cancel();
    _catchUpTimer = Timer(_catchUpDebounce, () {
      _catchUpTimer = null;
      if (!isClosed) {
        unawaited(fetch(showLoading: false));
      }
    });
  }

  /// One refresh per Request, coalesced: a surface move announces the Request
  /// once per hop and the desk should re-read once, not once per announcement.
  ///
  /// The whole desk is re-read rather than the single Request: the card may be
  /// leaving, and a projection that dropped only the row it was told about
  /// would leave the archived list and the counters saying something else.
  void _onRequestInvalidated(String beaconId) {
    if (isClosed || beaconId.isEmpty) return;
    _invalidationTimers.remove(beaconId)?.cancel();
    _invalidationTimers[beaconId] = Timer(_deskRelevantDebounce, () {
      _invalidationTimers.remove(beaconId);
      if (!isClosed) {
        unawaited(fetch(showLoading: false));
      }
    });
  }

  void _onDeskRelevantInvalidation(BeaconRoomInvalidation invalidation) {
    final beaconId = invalidation.beaconId;
    if (isClosed || beaconId.isEmpty) return;
    _deskRelevantTimers.remove(beaconId)?.cancel();
    _deskRelevantTimers[beaconId] = Timer(_deskRelevantDebounce, () {
      _deskRelevantTimers.remove(beaconId);
      if (!isClosed) {
        unawaited(fetch(showLoading: false));
        if (invalidation.entityType == BeaconRoomEntityType.roomMessage) {
          _scheduleRoomMessageHintRetry(beaconId);
        }
      }
    });
  }

  void _scheduleRoomMessageHintRetry(String beaconId) {
    _roomMessageHintRetryTimers.remove(beaconId)?.cancel();
    _roomMessageHintRetryTimers[beaconId] = Timer(_roomMessageHintRetryDelay, () {
      _roomMessageHintRetryTimers.remove(beaconId);
      if (!isClosed) {
        unawaited(fetch(showLoading: false));
      }
    });
  }

  Future<void> fetch({bool showLoading = true}) async {
    if (_fetchInFlight) {
      _fetchQueued = true;
      return;
    }
    await _runFetch(showLoading: showLoading);
  }

  Future<void> _runFetch({required bool showLoading}) async {
    _fetchInFlight = true;
    _fetchQueued = false;
    try {
      final seq = ++_fetchSeq;
      final filterBefore = state.filter;
      if (showLoading) {
        emit(
          state.copyWith(
            status: StateStatus.isLoading,
            archivedFetchInProgress: false,
            nonArchivedProjectionLoaded: false,
          ),
        );
      }
      try {
        final init = await _myWorkCase.loadDeskInit(userId: _userId);
        if (isClosed || seq != _fetchSeq) {
          return;
        }
        final withReviewWindows = await _myWorkCase.loadReviewWindows(
          init.nonArchivedCards,
          userId: _userId,
        );
        if (isClosed || seq != _fetchSeq) {
          return;
        }
        final merged = mergeMyWorkDeskCards(
          serverCards: withReviewWindows,
          localCards: state.nonArchivedCards,
          preferIds: _pendingDeskBeaconIds,
        );
        final mergedIds = merged.map((c) => c.beaconId).toSet();
        final stillPending = _pendingDeskBeaconIds.difference(mergedIds);
        _pendingDeskBeaconIds.removeWhere(mergedIds.contains);
        emit(
          state.copyWith(
            status: const StateIsSuccess(),
            loadError: null,
            nonArchivedProjectionLoaded: true,
            nonArchivedCards: merged,
            archivedCountHint: init.archivedCountHint,
            archivedCards: const [],
            archivedDataFetched: false,
          ),
        );
        _schedulePendingRetryIfNeeded(stillPending);
        await _loadAttentionIfEnabled(seq);
        if (filterBefore == MyWorkFilter.archived) {
          emit(state.copyWith(archivedFetchInProgress: true));
          unawaited(_loadArchived(seq));
        }
      } catch (e) {
        if (isClosed || seq != _fetchSeq) {
          return;
        }
        if (_shouldShowFullScreenLoadError(showLoading: showLoading)) {
          emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
        }
      }
    } finally {
      _fetchInFlight = false;
      if (_fetchQueued && !isClosed) {
        _fetchQueued = false;
        unawaited(_runFetch(showLoading: false));
      }
    }
  }

  Future<void> archiveBeacon(String beaconId) async {
    final cardIndex = state.nonArchivedCards.indexWhere(
      (c) => c.beaconId == beaconId,
    );
    final card = cardIndex >= 0 ? state.nonArchivedCards[cardIndex] : null;
    if (card != null && card.viewerArchived) {
      return;
    }

    await _myWorkCase.archiveBeacon(beaconId: beaconId, userId: _userId);
    _pendingDeskBeaconIds.remove(beaconId);

    final updated = card == null
        ? null
        : myWorkCardAfterArchiveRevocation(card);
    if (updated == null) {
      _removeBeaconFromState(beaconId);
    } else if (cardIndex >= 0) {
      final nextCards = List<MyWorkCardViewModel>.from(state.nonArchivedCards);
      nextCards[cardIndex] = updated;
      emit(state.copyWith(nonArchivedCards: nextCards));
    }

    emit(
      state.copyWith(
        archivedCountHint: state.archivedCountHint + 1,
        archivedDataFetched: false,
      ),
    );
  }

  Future<void> unarchiveBeacon(String beaconId) async {
    await _myWorkCase.unarchiveBeacon(beaconId: beaconId, userId: _userId);
    emit(
      state.copyWith(
        archivedCards: state.archivedCards
            .where((c) => c.beaconId != beaconId)
            .toList(),
        archivedCountHint: state.archivedCountHint > 0
            ? state.archivedCountHint - 1
            : 0,
      ),
    );
    unawaited(fetch());
  }

  void setFilter(MyWorkFilter filter) {
    if (filter == MyWorkFilter.archived &&
        !state.archivedDataFetched &&
        !state.archivedFetchInProgress) {
      emit(state.copyWith(filter: filter, archivedFetchInProgress: true));
      unawaited(_loadArchived(_fetchSeq));
      return;
    }
    emit(state.copyWith(filter: filter));
  }

  void setSort(MyWorkSort sort) {
    if (state.sort == sort) return;
    emit(state.copyWith(sort: sort));
  }

  Future<void> _loadArchived(int seq) async {
    try {
      final archived = await _myWorkCase.loadDeskArchived(userId: _userId);
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          archivedFetchInProgress: false,
          archivedDataFetched: true,
          archivedCards: archived.archivedCards,
          loadError: null,
          status: const StateIsSuccess(),
        ),
      );
      await _loadAttentionIfEnabled(seq);
    } catch (e) {
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          archivedFetchInProgress: false,
          loadError: _shouldShowArchivedLoadError() ? e : null,
          status: const StateIsSuccess(),
        ),
      );
    }
  }

  void _onBeaconChanged(RepositoryEvent<Beacon> event) => switch (event) {
    RepositoryEventCreate<Beacon>(value: final b) ||
    RepositoryEventUpdate<Beacon>(
      value: final b,
    ) => _onAuthoredBeaconChanged(b),
    RepositoryEventInvalidate<Beacon>() => unawaited(fetch(showLoading: false)),
    RepositoryEventDelete<Beacon>(value: final b) => _onBeaconDeleted(b.id),
    _ => null,
  };

  void _onAuthoredBeaconChanged(Beacon beacon) {
    if (beacon.id.isEmpty || beacon.author.id != _userId) {
      unawaited(fetch(showLoading: false));
      return;
    }
    _pendingDeskBeaconIds.add(beacon.id);
    emit(
      state.copyWith(
        status: const StateIsSuccess(),
        nonArchivedCards: upsertAuthoredMyWorkCard(
          state.nonArchivedCards,
          beacon,
        ),
      ),
    );
    unawaited(fetch(showLoading: false));
  }

  void _onBeaconDeleted(String beaconId) {
    _pendingDeskBeaconIds.remove(beaconId);
    _removeBeaconFromState(beaconId);
  }

  void _schedulePendingRetryIfNeeded(Set<String> stillPending) {
    _pendingRetryTimer?.cancel();
    if (stillPending.isEmpty || isClosed) {
      return;
    }
    final retryIds = Set<String>.from(stillPending);
    _pendingRetryTimer = Timer(_pendingRetryDelay, () {
      if (isClosed) {
        return;
      }
      unawaited(_retryPendingDesk(retryIds));
    });
  }

  Future<void> _retryPendingDesk(Set<String> retryIds) async {
    await fetch(showLoading: false);
    _pendingDeskBeaconIds.removeAll(retryIds);
  }

  void _removeBeaconFromState(String beaconId) {
    emit(
      state.copyWith(
        nonArchivedCards: state.nonArchivedCards
            .where((c) => c.beaconId != beaconId)
            .toList(),
        archivedCards: state.archivedCards
            .where((c) => c.beaconId != beaconId)
            .toList(),
      ),
    );
  }

  bool _shouldShowFullScreenLoadError({required bool showLoading}) {
    if (showLoading) {
      return true;
    }
    return state.nonArchivedCards.isEmpty &&
        (state.filter != MyWorkFilter.archived || state.archivedCards.isEmpty);
  }

  bool _shouldShowArchivedLoadError() =>
      state.filter == MyWorkFilter.archived && state.archivedCards.isEmpty;

  /// Clears one **optional** event off a Request (the × on a mini-card).
  ///
  /// An obligation has no such route: U07b removed generic settlement and the
  /// server refuses it, so this drops the receipt from the optional projection
  /// only and leaves every live obligation alone (D04, §5).
  Future<void> clearOptionalEvent(String beaconId, String receiptId) async {
    if (beaconId.isEmpty || receiptId.isEmpty) return;
    final current = state.attentionByBeacon[beaconId];
    if (current != null &&
        current.liveObligations.any((r) => r.id == receiptId)) {
      return;
    }
    // R6 — kept so the removal stays reversible. Everything below has to be
    // able to put this row back: a refusal is an answer, not a delay.
    final previous = current;
    if (current != null) {
      emit(
        state.copyWith(
          attentionByBeacon: {
            ...state.attentionByBeacon,
            beaconId: current.copyWith(
              unseenCount: current.unseenCount > 0
                  ? current.unseenCount - 1
                  : 0,
              latestUnseen: current.latestUnseen?.id == receiptId
                  ? null
                  : current.latestUnseen,
            ),
          },
        ),
      );
    }
    final AttentionClearResult result;
    try {
      result = await _myWorkCase.clearReceipt(receiptId);
    } catch (_) {
      _restoreAttention(beaconId, previous);
      await fetch(showLoading: false);
      rethrow;
    }
    if (isClosed) return;
    if (!result.appliedReceiptIds.contains(receiptId)) {
      // `skipped`, `denied`, `stale` — or simply a receipt the server did
      // not touch. None of them is a clear.
      _restoreAttention(beaconId, previous);
      return;
    }
    // Applied. The client holds one preview, not the list, so it cannot know
    // what the card shows next — only the server can say. Re-read this one
    // Request and adopt the answer whole, rather than leaving a card that
    // has a total and nothing to render (the derivation zeroes exactly that).
    await _adoptServerAttention(beaconId, fallback: previous);
  }

  void _restoreAttention(String beaconId, MyWorkBeaconAttention? previous) {
    if (isClosed || previous == null) return;
    emit(
      state.copyWith(
        attentionByBeacon: {
          ...state.attentionByBeacon,
          beaconId: previous,
        },
      ),
    );
  }

  Future<void> _adoptServerAttention(
    String beaconId, {
    required MyWorkBeaconAttention? fallback,
  }) async {
    final Map<String, MyWorkBeaconAttention> fresh;
    try {
      fresh = await _myWorkCase.loadMyWorkAttention({beaconId});
    } catch (_) {
      // The clear did land; only the re-read failed. Leave the optimistic
      // projection in place and let the next refresh reconcile it.
      return;
    }
    if (isClosed) return;
    final row = fresh[beaconId];
    if (row == null) return;
    emit(
      state.copyWith(
        attentionByBeacon: {
          ...state.attentionByBeacon,
          beaconId: row,
        },
      ),
    );
  }

  /// Optimistically zeroes the card's unseen badge as the Request opens.
  ///
  /// It does **not** mark anything read: §4's open gesture is a *clear*, and
  /// the detail host applies it once the Request has displayed. Marking read
  /// here was the read axis standing in for the clear axis (D02), and it also
  /// fired before navigation, so a forbidden open still burned the badge.
  Future<void> openedBeacon(String beaconId) async {
    if (beaconId.isEmpty) return;
    final current = state.attentionByBeacon[beaconId];
    if (current != null && current.unseenCount > 0) {
      emit(
        state.copyWith(
          attentionByBeacon: {
            ...state.attentionByBeacon,
            beaconId: current.copyWith(unseenCount: 0),
          },
        ),
      );
    }
  }

  Future<void> _loadAttentionIfEnabled(int seq) async {
    final beaconIds = {
      for (final c in state.nonArchivedCards) c.beaconId,
      for (final c in state.archivedCards) c.beaconId,
    };
    if (beaconIds.isEmpty) {
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          attentionByBeacon: const {},
          attentionLoaded: true,
        ),
      );
      return;
    }
    emit(state.copyWith(attentionLoaded: false));
    try {
      final attentionByBeacon = await _myWorkCase.loadMyWorkAttention(
        beaconIds,
      );
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(
        state.copyWith(
          attentionByBeacon: attentionByBeacon,
          attentionLoaded: true,
        ),
      );
    } catch (_) {
      if (isClosed || seq != _fetchSeq) {
        return;
      }
      emit(state.copyWith(attentionLoaded: false));
    }
  }
}
