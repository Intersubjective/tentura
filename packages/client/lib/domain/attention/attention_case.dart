import 'dart:async';
import 'dart:math' as math;

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';
import 'package:uuid/uuid.dart';

import 'package:tentura/consts.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import 'package:tentura/features/block/domain/use_case/block_case.dart';

import 'attention_ack_store.dart';
import 'attention_clear_store.dart';
import 'entity/activity_beacon_attention.dart';
import 'entity/attention_clear.dart';
import 'entity/attention_cursor.dart';
import 'entity/activity_offer_sort_row.dart';
import 'entity/attention_feed.dart';
import 'entity/attention_receipt.dart';
import 'entity/attention_summary.dart';
import 'entity/my_work_beacon_attention.dart';
import 'feed_session_registry.dart';
import 'port/attention_account_port.dart';
import 'port/attention_repository_port.dart';
import 'qa_attention_latency_probe.dart';

/// QA-only measurement of receipt commit to head-snapshot emission latency.
final class AttentionHeadRefreshLatency {
  const AttentionHeadRefreshLatency({
    required this.latency,
    required this.receiptCreatedAt,
    required this.measuredAt,
  });

  final Duration latency;
  final DateTime receiptCreatedAt;
  final DateTime measuredAt;
}

/// The sole owner that converts notification hints into attention feed refreshes.
@lazySingleton
final class AttentionCase {
  AttentionCase(
    this._repository,
    this._account,
    this._realtime,
    this._blockCase,
    this._feedSessions,
    this._logger, {
    @ignoreParam @visibleForTesting bool? qaLatencyMeasurementEnabled,
  }) : _qaLatencyMeasurementEnabled =
           qaLatencyMeasurementEnabled ?? kQaIntegrationTestMode {
    if (_qaLatencyMeasurementEnabled) {
      _qaLatencySamples = StreamController<AttentionHeadRefreshLatency>.broadcast();
    }
    _start();
  }

  final AttentionRepositoryPort _repository;
  final AttentionAccountPort _account;
  final RealtimeSyncCase _realtime;
  final BlockCase _blockCase;
  final FeedSessionRegistry _feedSessions;
  final Logger _logger;
  final bool _qaLatencyMeasurementEnabled;
  final AttentionAckStore _acks = AttentionAckStore();
  final AttentionClearStore _clears = AttentionClearStore();
  static const _uuid = Uuid();
  final _snapshot = BehaviorSubject<AttentionFeedSnapshot>.seeded(
    const AttentionFeedSnapshot(),
  );
  final _surfaceSummarySubject =
      BehaviorSubject<AttentionSurfaceSummary>.seeded(
        const AttentionSurfaceSummary(
          activityUnreadTotal: 0,
          myWorkUnreadTotal: 0,
          needsYouTotal: 0,
        ),
      );
  final Map<String, AttentionReceipt> _receiptsById = {};

  StreamSubscription<String>? _accountSub;
  StreamSubscription<RealtimeEntityChange>? _notificationSub;
  StreamSubscription<RealtimeCatchUp>? _catchUpSub;
  StreamSubscription<dynamic>? _blockSub;
  bool _surfaceSummaryRefreshInFlight = false;
  bool _surfaceSummaryRefreshQueued = false;
  int _surfaceSummaryRequestSerial = 0;

  /// Bumped when a mutation starts and again when it settles, so that any
  /// read overlapping it is discarded rather than allowed to overwrite the
  /// answer that mutation produced (D14).
  int _mutationSerial = 0;
  String _accountId = '';
  int _accountGeneration = 0;
  final Map<String, bool> _headRefreshInFlight = {};
  final Map<String, bool> _headRefreshQueued = {};
  Future<void> _markAllSeenChain = Future.value();
  final Map<String, Future<void>> _ackChains = {};
  StreamController<AttentionHeadRefreshLatency>? _qaLatencySamples;
  AttentionHeadRefreshLatency? _lastQaHeadRefreshLatency;

  Stream<AttentionHeadRefreshLatency>? get qaHeadRefreshLatencies =>
      _qaLatencySamples?.stream;

  AttentionHeadRefreshLatency? get lastQaHeadRefreshLatency =>
      _qaLatencyMeasurementEnabled ? _lastQaHeadRefreshLatency : null;

  Stream<AttentionSummary> get unreadSummary =>
      _snapshot.stream.map((snapshot) => snapshot.summary).distinct();

  Stream<AttentionSurfaceSummary> get surfaceSummary =>
      _surfaceSummarySubject.stream.distinct();

  Stream<AttentionFeedSnapshot> get feedPages => _snapshot.stream;

  AttentionFeedSnapshot get snapshot => _snapshot.value;

  AttentionFeedSession feedSession(String destinationId) =>
      _feedSessions.session(destinationId);

  Stream<AttentionFeedSession> watchFeedSession(String destinationId) =>
      _feedSessions.watch(destinationId);

  void attachFeedSession(String destinationId) {
    _feedSessions.attach(destinationId);
  }

  void detachFeedSession(String destinationId) {
    _feedSessions.detach(destinationId);
  }

  void _start() {
    _accountSub = _account.currentAccountChanges.listen(_onAccountChanged);
    _notificationSub = _realtime
        .changesFor(const {
          RealtimeEntityKind.notification,
          RealtimeEntityKind.helpOffer,
          RealtimeEntityKind.inboxItem,
        })
        .listen(_onRealtimeEntityChange);
    _catchUpSub = _realtime.catchUps.listen((_) {
      _requestHeadRefreshForAllAttached();
      unawaited(_requestSurfaceSummaryRefresh());
    });
    _blockSub = _blockCase.changes.listen((_) {
      _requestHeadRefreshForAllAttached();
      unawaited(_requestSurfaceSummaryRefresh());
    });
  }

  void _onRealtimeEntityChange(RealtimeEntityChange change) {
    unawaited(_requestSurfaceSummaryRefresh());
    if (change.kind == RealtimeEntityKind.helpOffer ||
        change.kind == RealtimeEntityKind.inboxItem) {
      _requestHeadRefreshForAttachedActivityStream();
    } else {
      _requestHeadRefreshForAllAttached();
    }
  }

  void _onAccountChanged(String accountId) {
    if (accountId == _accountId) return;
    _accountId = accountId;
    _accountGeneration++;
    _headRefreshQueued.clear();
    _headRefreshInFlight.clear();
    _receiptsById.clear();
    _ackChains.clear();
    _markAllSeenChain = Future.value();
    _acks.resetForAccount(accountId);
    _clears.resetForAccount(accountId);
    _feedSessions.resetForAccount();
    _emit(const AttentionFeedSnapshot());
    _surfaceSummarySubject.add(
      const AttentionSurfaceSummary(
        activityUnreadTotal: 0,
        myWorkUnreadTotal: 0,
        needsYouTotal: 0,
      ),
    );
    _surfaceSummaryRequestSerial = 0;
    if (accountId.isNotEmpty) {
      _requestHeadRefreshForAllAttached();
      unawaited(_requestSurfaceSummaryRefresh());
    }
  }

  void setActiveView(String destinationId, AttentionView view) {
    final session = _feedSessions.session(destinationId);
    if (session.activeView == view) return;
    _feedSessions.update(
      destinationId,
      session.copyWith(
        activeView: view,
        requestGeneration: session.requestGeneration + 1,
        headRefreshError: null,
      ),
    );
    unawaited(_requestHeadRefresh(destinationId));
  }

  void setSearch(String destinationId, String? value) {
    final normalized = value?.trim();
    final next = normalized == null || normalized.isEmpty ? '' : normalized;
    final session = _feedSessions.session(destinationId);
    if (session.searchText == next) return;
    _feedSessions.update(
      destinationId,
      session.copyWith(
        searchText: next,
        pages: const {},
        requestGeneration: session.requestGeneration + 1,
        headRefreshError: null,
      ),
    );
    unawaited(_requestHeadRefresh(destinationId));
  }

  Future<void> refresh({
    String destinationId = AttentionFeedDestinationId.activityStream,
  }) async =>
      _requestHeadRefresh(destinationId);

  /// Returns unread attention for candidate Beacons without assigning them to
  /// any presentation surface. Surface projection belongs to the client
  /// presenter that owns the current Inbox and My Work snapshots.
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) {
    if (beaconIds.isEmpty) return Future.value(const {});
    return _repository.unreadForBeacons(beaconIds);
  }

  Future<Set<String>> liveObligationBeacons() =>
      _repository.liveObligationBeacons();

  Future<List<MyWorkBeaconAttention>> myWorkAttention(Set<String> beaconIds) {
    if (beaconIds.isEmpty) {
      return Future.value(const []);
    }
    return _repository.myWorkAttention(beaconIds);
  }

  Future<ActivityOfferPage> activityOffers({
    String? cursor,
    int limit = 20,
  }) =>
      _repository.activityOffers(cursor: cursor, limit: limit);

  Future<ActivityBeaconAttention> activityAttention({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) =>
      _repository.activityAttention(
        beaconId: beaconId,
        cursor: cursor,
        limit: limit,
      );

  Future<void> fetchNextPage({
    String destinationId = AttentionFeedDestinationId.activityStream,
  }) async {
    if (_accountId.isEmpty) return;
    final session = _feedSessions.session(destinationId);
    final view = session.activeView;
    final search = session.normalizedSearch;
    final current = session.pages[view];
    final cursor = current?.nextCursor;
    if (cursor == null || cursor.isEmpty) return;
    // A cursor from an older generation was minted under different sort keys.
    // Resuming from it would drop or repeat rows without saying so, so it is
    // not sent at all — the session resets and re-reads the head.
    if (AttentionCursorContract.isKnownStale(cursor)) {
      await _resetStaleCursor(destinationId, reason: 'cursor generation');
      return;
    }
    final accountGeneration = _accountGeneration;
    final requestGeneration = session.requestGeneration;
    final mutationSerial = _mutationSerial;
    final AttentionFeed feed;
    try {
      feed = await _repository.fetch(
        view: view,
        cursor: cursor,
        search: search,
        surface: surfaceForDestination(destinationId),
      );
    } on Object catch (error) {
      // The server refused the cursor at decode. Retrying the tail can only
      // fail again; reset and re-read the head instead.
      if (!AttentionCursorContract.isStaleCursorError(error)) rethrow;
      await _resetStaleCursor(destinationId, reason: '$error');
      return;
    }
    if (accountGeneration != _accountGeneration) return;
    if (mutationSerial != _mutationSerial) return;
    final landed = _feedSessions.session(destinationId);
    if (landed.requestGeneration != requestGeneration) return;
    _applyPage(
      destinationId,
      feed,
      view: view,
      replaceHead: false,
    );
  }

  /// Drops every held page cursor for [destinationId], bumps the session's
  /// request generation so responses already in flight cannot land, and
  /// re-reads the head. The tail is never retried.
  Future<void> _resetStaleCursor(
    String destinationId, {
    required String reason,
  }) async {
    final session = _feedSessions.session(destinationId);
    _logger.info('Attention cursor reset ($destinationId): $reason');
    _feedSessions.update(
      destinationId,
      session.copyWith(
        pages: {
          for (final entry in session.pages.entries)
            entry.key: entry.value.copyWith(nextCursor: null),
        },
        requestGeneration: session.requestGeneration + 1,
        headRefreshError: null,
      ),
    );
    await _requestHeadRefresh(destinationId);
  }

  Future<void> markSeen(Iterable<String> ids) async {
    final pending = ids.toSet();
    if (pending.isEmpty) return;
    final generation = _accountGeneration;
    final unreadDelta = _displayedUnreadCount(pending);
    final surfaceDeltas = _surfaceUnreadDeltasForIds(pending, seen: false);
    final token = _acks.markSeen(pending);
    _applyOptimisticAcks(unreadDelta: -unreadDelta);
    _applyOptimisticSurfaceSummary(
      activityUnreadDelta: -surfaceDeltas.activity,
      myWorkUnreadDelta: -surfaceDeltas.myWork,
    );
    try {
      await _runAfterAckBarriers(pending, generation, () async {
        final still = pending.where((id) => _acks.hasToken(id, token)).toSet();
        if (still.isEmpty) return;
        await _repository.markSeen(still.toList(growable: false));
        if (generation != _accountGeneration) return;
        _acks.markCommitted(still, token);
      });
    } catch (error, stackTrace) {
      if (generation == _accountGeneration) {
        _acks.discard(pending, token: token);
        _applyOptimisticAcks(unreadDelta: unreadDelta);
        _applyOptimisticSurfaceSummary(
          activityUnreadDelta: surfaceDeltas.activity,
          myWorkUnreadDelta: surfaceDeltas.myWork,
        );
      }
      _logger.warning('Attention mark-seen failed', error, stackTrace);
      rethrow;
    }
    if (generation == _accountGeneration) {
      _requestHeadRefreshForAllAttached();
      unawaited(_requestSurfaceSummaryRefresh());
    }
  }

  Future<void> markUnseen(Iterable<String> ids) async {
    final pending = ids.toSet();
    if (pending.isEmpty) return;
    final generation = _accountGeneration;
    final unreadDelta = _displayedSeenCount(pending);
    final surfaceDeltas = _surfaceUnreadDeltasForIds(pending, seen: true);
    final token = _acks.markUnseen(pending);
    _applyOptimisticAcks(unreadDelta: unreadDelta);
    _applyOptimisticSurfaceSummary(
      activityUnreadDelta: surfaceDeltas.activity,
      myWorkUnreadDelta: surfaceDeltas.myWork,
    );
    try {
      await _runAfterAckBarriers(pending, generation, () async {
        final still = pending.where((id) => _acks.hasToken(id, token)).toSet();
        if (still.isEmpty) return;
        final updated = await _repository.markUnseen(
          still.toList(growable: false),
        );
        if (generation != _accountGeneration) return;
        if (updated == 0) {
          _acks.discard(still, token: token);
          _applyOptimisticAcks(unreadDelta: -unreadDelta);
          _applyOptimisticSurfaceSummary(
            activityUnreadDelta: -surfaceDeltas.activity,
            myWorkUnreadDelta: -surfaceDeltas.myWork,
          );
          return;
        }
        _acks.markCommitted(still, token);
      });
    } catch (error, stackTrace) {
      if (generation == _accountGeneration) {
        _acks.discard(pending, token: token);
        _applyOptimisticAcks(unreadDelta: -unreadDelta);
        _applyOptimisticSurfaceSummary(
          activityUnreadDelta: -surfaceDeltas.activity,
          myWorkUnreadDelta: -surfaceDeltas.myWork,
        );
      }
      _logger.warning('Attention mark-unseen failed', error, stackTrace);
      rethrow;
    }
    if (generation == _accountGeneration) {
      _requestHeadRefreshForAllAttached();
      unawaited(_requestSurfaceSummaryRefresh());
    }
  }

  Future<void> markSeenForBeacon(String beaconId) async {
    if (beaconId.isEmpty) return;
    final pending = _receiptsById.values
        .where(
          (receipt) =>
              receipt.beaconId == beaconId && !_displaysSeen(receipt.id),
        )
        .map((receipt) => receipt.id)
        .toSet();
    final generation = _accountGeneration;
    final unreadDelta = _displayedUnreadCount(pending);
    final surfaceDeltas = _surfaceUnreadDeltasForIds(pending, seen: false);
    final token = pending.isEmpty
        ? null
        : _acks.markSeen(pending);
    if (token != null) {
      _applyOptimisticAcks(unreadDelta: -unreadDelta);
      _applyOptimisticSurfaceSummary(
        activityUnreadDelta: -surfaceDeltas.activity,
        myWorkUnreadDelta: -surfaceDeltas.myWork,
      );
    }
    try {
      await _runAfterAckBarriers(pending, generation, () async {
        if (generation != _accountGeneration) return;
        await _repository.markSeenForBeacon(beaconId);
        if (generation != _accountGeneration) return;
        if (token != null) {
          _acks.markCommitted(pending, token);
        }
      });
    } catch (error, stackTrace) {
      if (generation == _accountGeneration && token != null) {
        _acks.discard(pending, token: token);
        _applyOptimisticAcks(unreadDelta: unreadDelta);
        _applyOptimisticSurfaceSummary(
          activityUnreadDelta: surfaceDeltas.activity,
          myWorkUnreadDelta: surfaceDeltas.myWork,
        );
      }
      _logger.warning(
        'Attention mark-seen-for-beacon failed',
        error,
        stackTrace,
      );
      rethrow;
    }
    if (generation == _accountGeneration) {
      _requestHeadRefreshForAllAttached();
      unawaited(_requestSurfaceSummaryRefresh());
    }
  }

  Future<void> markAllSeen({AttentionSurface? surface}) async {
    final ids = _receiptsById.values
        .where((receipt) => !_displaysSeen(receipt.id))
        .where((receipt) => surface == null || receipt.surface == surface)
        .map((receipt) => receipt.id)
        .toSet();
    final generation = _accountGeneration;
    final previousUnread = snapshot.summary.unreadTotal;
    final previousSurface = _surfaceSummarySubject.value;
    final token = _acks.markAllSeen(ids);
    final unreadDelta = _displayedUnreadCount(ids);
    if (surface == null) {
      _applyOptimisticAcks(unreadTotal: 0);
    } else {
      _applyOptimisticAcks(unreadDelta: -unreadDelta);
    }
    _applyOptimisticSurfaceSummary(
      activityUnreadTotal: surface == null || surface == AttentionSurface.activity
          ? 0
          : null,
      myWorkUnreadTotal: surface == null || surface == AttentionSurface.myWork
          ? 0
          : null,
    );
    final previous = _markAllSeenChain;
    final op = previous.catchError((_) {}).then((_) async {
      await Future.wait([
        for (final chain in _ackChains.values) chain.catchError((_) {}),
      ]);
      if (generation != _accountGeneration) return;
      try {
        await _repository.markAllSeen(surface: surface);
        if (generation != _accountGeneration) return;
        _acks.markCommitted(ids, token);
      } catch (error, stackTrace) {
        if (generation == _accountGeneration) {
          _acks.discard(ids, token: token);
          _applyOptimisticAcks(unreadTotal: previousUnread);
          _surfaceSummarySubject.add(previousSurface);
        }
        _logger.warning('Attention mark-all-seen failed', error, stackTrace);
        rethrow;
      }
    });
    _markAllSeenChain = op.catchError((_) {});
    await op;
    if (generation == _accountGeneration) {
      _requestHeadRefreshForAllAttached();
      unawaited(_requestSurfaceSummaryRefresh());
    }
  }

  Future<void> settle(String receiptId) async {
    final receipt = _receiptsById[receiptId];
    if (receipt == null || !receipt.isUserSettleable) return;
    await settleReceipt(receiptId);
  }

  Future<void> settleReceipt(String receiptId) async {
    if (receiptId.isEmpty) return;
    final receipt = _receiptsById[receiptId];
    if (receipt != null && !receipt.isUserSettleable) return;
    await _repository.settle(receiptId: receiptId, kind: 'resolved');
    _requestHeadRefreshForAllAttached();
    unawaited(_requestSurfaceSummaryRefresh());
  }

  /// Clears the optional attention a Request accumulated, because it was
  /// opened. Never touches an obligation: the capture is the server's.
  Future<AttentionClearResult> clearRequestOpen({
    required String beaconId,
  }) => _clear(
    kind: AttentionClearCaptureKind.requestOpen,
    beaconId: beaconId,
  );

  /// Clears one event or card by hand.
  Future<AttentionClearResult> clearReceipt({
    required String receiptId,
  }) => _clear(
    kind: AttentionClearCaptureKind.explicit,
    receiptId: receiptId,
  );

  Future<AttentionClearResult> _clear({
    required AttentionClearCaptureKind kind,
    String? beaconId,
    String? receiptId,
  }) async {
    final generation = _accountGeneration;
    final operationId = _uuid.v4();
    _mutationSerial++;
    try {
      final snapshot = await _repository.clearSnapshot(
        kind: kind,
        beaconId: beaconId,
        receiptId: receiptId,
      );
      if (generation != _accountGeneration) {
        return AttentionClearResult(
          operationId: operationId,
          status: AttentionOperationStatus.stale,
        );
      }
      return await _applyClearOptimistically(
        operationId: operationId,
        memberIds: snapshot.receiptIds,
        run: () => _repository.clear(
          snapshotToken: snapshot.snapshotToken,
          operationId: operationId,
        ),
        appliedIdsOf: (result) => result.appliedReceiptIds,
        generation: generation,
      );
    } finally {
      _mutationSerial++;
      if (generation == _accountGeneration) {
        _requestHeadRefreshForAllAttached();
        unawaited(_requestSurfaceSummaryRefresh());
      }
    }
  }

  /// Bounded sweep of everything currently dismissible. Resume a `partial`
  /// answer by passing the **same** [operationId] back: a fresh id would make
  /// the server capture a second membership.
  Future<AttentionDismissAllResult> dismissAll({
    String? operationId,
    int? maxBatches,
  }) async {
    final generation = _accountGeneration;
    final id = operationId ?? _uuid.v4();
    // The client can only be optimistic about rows it has actually loaded;
    // unloaded totals stay where they are (D14).
    final loaded = _receiptsById.values
        .where((receipt) => !receipt.isCleared)
        .map((receipt) => receipt.id)
        .toSet();
    _mutationSerial++;
    try {
      return await _applyClearOptimistically(
        operationId: id,
        memberIds: loaded,
        run: () => _repository.dismissAll(
          operationId: id,
          maxBatches: maxBatches,
        ),
        appliedIdsOf: (result) => result.appliedReceiptIds,
        generation: generation,
      );
    } finally {
      _mutationSerial++;
      if (generation == _accountGeneration) {
        _requestHeadRefreshForAllAttached();
        unawaited(_requestSurfaceSummaryRefresh());
      }
    }
  }

  /// Restores what [operationId] applied, within the server's window.
  ///
  /// Undo is deliberately **not** optimistic. It is rare, it is bounded, and
  /// it can be refused outright — showing rows back before the server agreed
  /// would turn a refusal into a flicker of false success.
  Future<AttentionUndoResult> undoDismissAll({
    required String operationId,
    required String undoToken,
  }) async {
    final generation = _accountGeneration;
    _mutationSerial++;
    try {
      final result = await _repository.undo(
        operationId: operationId,
        undoToken: undoToken,
      );
      if (generation != _accountGeneration) return result;
      if (result.isRefused) {
        // Nothing moved. The rows stay cleared and the caller reports why.
        _logger.info(
          'Attention undo refused: ${result.refusal?.wireName} ($operationId)',
        );
        return result;
      }
      _clears.rollback(operationId, result.restoredReceiptIds);
      _applyOptimisticAcks();
      return result;
    } finally {
      _mutationSerial++;
      if (generation == _accountGeneration) {
        _requestHeadRefreshForAllAttached();
        unawaited(_requestSurfaceSummaryRefresh());
      }
    }
  }

  /// Repairs obligations and adopts the returned authoritative summary.
  ///
  /// The server does **not** invalidate sessions after a repair, so the
  /// client must refetch rather than assume its pages are current.
  Future<AttentionReconcileResult> reconcile() async {
    final generation = _accountGeneration;
    _mutationSerial++;
    try {
      final result = await _repository.reconcile();
      if (generation != _accountGeneration) return result;
      if (!_surfaceSummarySubject.isClosed) {
        _surfaceSummarySubject.add(result.summary);
      }
      return result;
    } finally {
      _mutationSerial++;
      if (generation == _accountGeneration) {
        _requestHeadRefreshForAllAttached();
        unawaited(_requestSurfaceSummaryRefresh());
      }
    }
  }

  /// Cleared and active attention for one Request.
  Future<AttentionFeedPage> requestHistory({
    required String beaconId,
    String? cursor,
    int limit = 20,
  }) => _repository.requestHistory(
    beaconId: beaconId,
    cursor: cursor,
    limit: limit,
  );

  Future<T> _applyClearOptimistically<T>({
    required String operationId,
    required Iterable<String> memberIds,
    required Future<T> Function() run,
    required List<String> Function(T result) appliedIdsOf,
    required int generation,
  }) async {
    final members = memberIds.toSet();
    final deltas = _surfaceUnreadDeltasForIds(members, seen: false);
    final unreadDelta = _displayedUnreadCount(members);
    if (members.isNotEmpty) {
      _clears.begin(operationId, members);
      _applyOptimisticAcks(unreadDelta: -unreadDelta);
      _applyOptimisticSurfaceSummary(
        activityUnreadDelta: -deltas.activity,
        myWorkUnreadDelta: -deltas.myWork,
      );
    }
    try {
      final result = await run();
      if (generation != _accountGeneration) return result;
      final applied = appliedIdsOf(result).toSet();
      // Only the members the server says it applied survive. A skipped, a
      // denied and an unanswered (still pending) member are all rolled back —
      // `partial` is not a slow `complete`.
      final withdrawn = members.difference(applied);
      _clears.commit(operationId, applied);
      if (withdrawn.isNotEmpty) {
        final restored = _surfaceUnreadDeltasForIds(withdrawn, seen: false);
        _applyOptimisticSurfaceSummary(
          activityUnreadDelta: restored.activity,
          myWorkUnreadDelta: restored.myWork,
        );
      }
      _applyOptimisticAcks(
        unreadDelta: withdrawn.isEmpty ? 0 : _displayedUnreadCount(withdrawn),
      );
      return result;
    } catch (error, stackTrace) {
      if (generation == _accountGeneration && members.isNotEmpty) {
        _clears.discard(operationId);
        _applyOptimisticAcks(unreadDelta: unreadDelta);
        _applyOptimisticSurfaceSummary(
          activityUnreadDelta: deltas.activity,
          myWorkUnreadDelta: deltas.myWork,
        );
      }
      // Destructive-looking gestures fail out loud; nothing is queued (D14).
      _logger.warning('Attention clear failed', error, stackTrace);
      rethrow;
    }
  }

  void _requestHeadRefreshForAttachedActivityStream() {
    for (final destinationId in _feedSessions.attachedDestinationIds) {
      if (destinationId == AttentionFeedDestinationId.activityStream) {
        unawaited(_requestHeadRefresh(destinationId));
      }
    }
  }

  Future<void> _requestSurfaceSummaryRefresh() async {
    if (_accountId.isEmpty) return;
    if (_surfaceSummaryRefreshInFlight) {
      _surfaceSummaryRefreshQueued = true;
      return;
    }
    _surfaceSummaryRefreshInFlight = true;
    final accountGeneration = _accountGeneration;
    final mutationSerial = _mutationSerial;
    final requestSerial = ++_surfaceSummaryRequestSerial;
    try {
      final summary = await _repository.surfaceSummary();
      if (accountGeneration != _accountGeneration) return;
      if (mutationSerial != _mutationSerial) return;
      if (requestSerial != _surfaceSummaryRequestSerial) return;
      if (!_surfaceSummarySubject.isClosed) {
        _surfaceSummarySubject.add(summary);
      }
    } catch (error, stackTrace) {
      if (accountGeneration != _accountGeneration) return;
      if (requestSerial != _surfaceSummaryRequestSerial) return;
      _logger.warning('Attention surface summary failed', error, stackTrace);
    } finally {
      _surfaceSummaryRefreshInFlight = false;
      if (_surfaceSummaryRefreshQueued) {
        _surfaceSummaryRefreshQueued = false;
        unawaited(_requestSurfaceSummaryRefresh());
      }
    }
  }

  void _requestHeadRefreshForAllAttached() {
    final attached = _feedSessions.attachedDestinationIds.toList();
    if (attached.isEmpty) {
      // The account-wide summary (unread badge) must keep converging even
      // when no feed screen is mounted to attach a destination — nothing
      // else refreshes `snapshot.summary`. Route through the default
      // destination so its session exists and gets pre-warmed for when it
      // is later attached.
      unawaited(_requestHeadRefresh(AttentionFeedDestinationId.activityStream));
      return;
    }
    for (final destinationId in attached) {
      unawaited(_requestHeadRefresh(destinationId));
    }
  }

  Future<void> _requestHeadRefresh(String destinationId) async {
    if (_accountId.isEmpty) return;
    if (_headRefreshInFlight[destinationId] == true) {
      _headRefreshQueued[destinationId] = true;
      return;
    }
    _headRefreshInFlight[destinationId] = true;
    final accountGeneration = _accountGeneration;
    final mutationSerial = _mutationSerial;
    final session = _feedSessions.session(destinationId);
    final requestGeneration = session.requestGeneration;
    final view = session.activeView;
    final search = session.normalizedSearch;
    try {
      final feed = await _repository.fetch(
        view: view,
        search: search,
        surface: surfaceForDestination(destinationId),
      );
      if (accountGeneration != _accountGeneration) return;
      // A page that left before a mutation cannot describe the world after
      // it; the mutation's own refresh is already queued behind this one.
      if (mutationSerial != _mutationSerial) return;
      final landed = _feedSessions.session(destinationId);
      if (landed.requestGeneration != requestGeneration) return;
      _applyPage(
        destinationId,
        feed,
        view: view,
        replaceHead: true,
      );
    } catch (error, stackTrace) {
      if (accountGeneration != _accountGeneration) return;
      final landed = _feedSessions.session(destinationId);
      if (landed.requestGeneration != requestGeneration) return;
      _feedSessions.update(
        destinationId,
        landed.copyWith(headRefreshError: error),
      );
      _logger.warning('Attention head refresh failed', error, stackTrace);
    } finally {
      _headRefreshInFlight[destinationId] = false;
      if (_headRefreshQueued[destinationId] == true) {
        _headRefreshQueued[destinationId] = false;
        unawaited(_requestHeadRefresh(destinationId));
      }
    }
  }

  void _applyPage(
    String destinationId,
    AttentionFeed feed, {
    required AttentionView view,
    required bool replaceHead,
  }) {
    final session = _feedSessions.session(destinationId);
    final oldPage = session.pages[view];
    for (final receipt in feed.page.items) {
      _receiptsById[receipt.id] = receipt;
    }
    final incoming = _uniqueByReceiptId(
      feed.page.items.map(_acks.apply).map(_clears.apply),
    );
    final items = replaceHead
        ? incoming
        : <AttentionReceipt>[...?oldPage?.items, ...incoming]
              .fold<Map<String, AttentionReceipt>>(
                {},
                (items, receipt) => items..[receipt.id] = receipt,
              )
              .values
              .toList(growable: false);
    final pages = Map<AttentionView, AttentionFeedPage>.from(session.pages)
      ..[view] = AttentionFeedPage(
        items: items,
        nextCursor: feed.page.nextCursor,
      );
    _feedSessions.update(
      destinationId,
      session.copyWith(
        pages: pages,
        headRefreshError: null,
      ),
    );
    _emit(
      snapshot.copyWith(
        summary: feed.summary.copyWith(
          unreadTotal: math.max(
            0,
            feed.summary.unreadTotal + _acks.pendingUnreadDelta(_receiptsById),
          ),
        ),
      ),
    );
    if (replaceHead) {
      _recordQaHeadRefreshLatency(items, DateTime.now().toUtc());
    }
  }

  Future<void> _runAfterAckBarriers(
    Set<String> ids,
    int accountGeneration,
    Future<void> Function() run,
  ) async {
    await Future.wait([
      _markAllSeenChain.catchError((_) {}),
      for (final id in ids) (_ackChains[id] ?? Future.value()).catchError((_) {}),
    ]);
    if (accountGeneration != _accountGeneration) return;
    final op = run();
    final tracked = op.catchError((_) {});
    for (final id in ids) {
      _ackChains[id] = tracked;
    }
    await op;
  }

  bool _displaysSeen(String id) {
    if (_acks.isOptimisticallyUnseen(id)) return false;
    if (_acks.isOptimisticallySeen(id)) return true;
    return _receiptsById[id]?.isSeen ?? false;
  }

  int _displayedUnreadCount(Iterable<String> ids) {
    var n = 0;
    for (final id in ids) {
      if (!_displaysSeen(id)) n++;
    }
    return n;
  }

  int _displayedSeenCount(Iterable<String> ids) {
    var n = 0;
    for (final id in ids) {
      if (_displaysSeen(id)) n++;
    }
    return n;
  }

  ({int activity, int myWork}) _surfaceUnreadDeltasForIds(
    Iterable<String> ids, {
    required bool seen,
  }) {
    var activity = 0;
    var myWork = 0;
    for (final id in ids) {
      final displaysSeen = _displaysSeen(id);
      if (seen && !displaysSeen) continue;
      if (!seen && displaysSeen) continue;
      final receipt = _receiptsById[id];
      if (receipt == null) continue;
      switch (receipt.surface) {
        case AttentionSurface.activity:
          activity++;
        case AttentionSurface.myWork:
          myWork++;
      }
    }
    return (activity: activity, myWork: myWork);
  }

  void _applyOptimisticSurfaceSummary({
    int activityUnreadDelta = 0,
    int myWorkUnreadDelta = 0,
    int? activityUnreadTotal,
    int? myWorkUnreadTotal,
    int? needsYouTotal,
  }) {
    final current = _surfaceSummarySubject.value;
    if (!_surfaceSummarySubject.isClosed) {
      _surfaceSummarySubject.add(
        current.copyWith(
          activityUnreadTotal:
              activityUnreadTotal ??
              math.max(0, current.activityUnreadTotal + activityUnreadDelta),
          myWorkUnreadTotal:
              myWorkUnreadTotal ??
              math.max(0, current.myWorkUnreadTotal + myWorkUnreadDelta),
          needsYouTotal: needsYouTotal ?? current.needsYouTotal,
        ),
      );
    }
  }

  void _applyOptimisticAcks({
    int unreadDelta = 0,
    int? unreadTotal,
  }) {
    for (final destinationId in _feedSessions.attachedDestinationIds) {
      final session = _feedSessions.session(destinationId);
      final pages = <AttentionView, AttentionFeedPage>{
        for (final entry in session.pages.entries)
          entry.key: entry.value.copyWith(
            items: [
              for (final receipt in entry.value.items)
                _clears.apply(_acks.apply(_receiptsById[receipt.id] ?? receipt)),
            ].where((receipt) {
              if (entry.key != AttentionView.unread) return true;
              return !receipt.isSeen;
            }).toList(growable: false),
          ),
      };
      _feedSessions.update(destinationId, session.copyWith(pages: pages));
    }
    final unread = math.max(
      0,
      unreadTotal ?? snapshot.summary.unreadTotal + unreadDelta,
    );
    _emit(
      snapshot.copyWith(
        summary: snapshot.summary.copyWith(unreadTotal: unread),
      ),
    );
  }

  List<AttentionReceipt> _uniqueByReceiptId(Iterable<AttentionReceipt> items) =>
      items
          .fold<Map<String, AttentionReceipt>>(
            {},
            (byId, receipt) => byId..[receipt.id] = receipt,
          )
          .values
          .toList(growable: false);

  void _emit(AttentionFeedSnapshot next) {
    if (!_snapshot.isClosed) _snapshot.add(next);
  }

  void _recordQaHeadRefreshLatency(
    List<AttentionReceipt> items,
    DateTime measuredAt,
  ) {
    if (!_qaLatencyMeasurementEnabled || items.isEmpty) return;
    final newest = items.reduce(
      (left, right) =>
          right.createdAt.isAfter(left.createdAt) ? right : left,
    );
    final sample = AttentionHeadRefreshLatency(
      latency: measuredAt.difference(newest.createdAt),
      receiptCreatedAt: newest.createdAt,
      measuredAt: measuredAt,
    );
    _lastQaHeadRefreshLatency = sample;
    _qaLatencySamples?.add(sample);
    QaAttentionLatencyProbe.publishHeadRefreshLatencyMs(
      sample.latency.inMilliseconds,
    );
    _logger.info(
      '[AttentionCase] attention_event=head_refresh_latency '
      'latency_ms=${sample.latency.inMilliseconds} '
      'receipt_created_at=${newest.createdAt.toUtc().toIso8601String()}',
    );
  }

  @disposeMethod
  Future<void> dispose() async {
    await _accountSub?.cancel();
    await _notificationSub?.cancel();
    await _catchUpSub?.cancel();
    await _blockSub?.cancel();
    await _qaLatencySamples?.close();
    await _snapshot.close();
    await _surfaceSummarySubject.close();
  }
}
