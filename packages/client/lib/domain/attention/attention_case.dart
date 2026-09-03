import 'dart:async';
import 'dart:math' as math;

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/consts.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import 'package:tentura/features/block/domain/use_case/block_case.dart';

import 'attention_ack_store.dart';
import 'entity/attention_feed.dart';
import 'entity/attention_receipt.dart';
import 'entity/attention_summary.dart';
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
  final Logger _logger;
  final bool _qaLatencyMeasurementEnabled;
  final AttentionAckStore _acks = AttentionAckStore();
  final _snapshot = BehaviorSubject<AttentionFeedSnapshot>.seeded(
    const AttentionFeedSnapshot(),
  );
  final Map<String, AttentionReceipt> _receiptsById = {};

  StreamSubscription<String>? _accountSub;
  StreamSubscription<RealtimeEntityChange>? _notificationSub;
  StreamSubscription<RealtimeCatchUp>? _catchUpSub;
  StreamSubscription<dynamic>? _blockSub;
  String _accountId = '';
  int _accountGeneration = 0;
  bool _headRefreshInFlight = false;
  bool _headRefreshQueued = false;
  String? _search;
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

  Stream<AttentionFeedSnapshot> get feedPages => _snapshot.stream;

  AttentionFeedSnapshot get snapshot => _snapshot.value;

  void _start() {
    _accountSub = _account.currentAccountChanges.listen(_onAccountChanged);
    _notificationSub = _realtime
        .changesFor(const {RealtimeEntityKind.notification})
        .listen((_) => _requestHeadRefresh());
    _catchUpSub = _realtime.catchUps.listen((_) => _requestHeadRefresh());
    _blockSub = _blockCase.changes.listen((_) => _requestHeadRefresh());
  }

  void _onAccountChanged(String accountId) {
    if (accountId == _accountId) return;
    _accountId = accountId;
    _accountGeneration++;
    _headRefreshQueued = false;
    _receiptsById.clear();
    _ackChains.clear();
    _markAllSeenChain = Future.value();
    _acks.resetForAccount(accountId);
    _emit(const AttentionFeedSnapshot());
    if (accountId.isNotEmpty) unawaited(_requestHeadRefresh());
  }

  void setActiveView(AttentionView view) {
    if (snapshot.activeView == view) return;
    _emit(snapshot.copyWith(activeView: view));
    unawaited(_requestHeadRefresh());
  }

  void setSearch(String? value) {
    final normalized = value?.trim();
    final next = normalized == null || normalized.isEmpty ? null : normalized;
    if (_search == next) return;
    _search = next;
    unawaited(_requestHeadRefresh());
  }

  Future<void> refresh() async => _requestHeadRefresh();

  /// Returns unread attention for candidate Beacons without assigning them to
  /// any presentation surface. Surface projection belongs to the client
  /// presenter that owns the current Inbox and My Work snapshots.
  Future<Set<String>> unreadForBeacons(Set<String> beaconIds) {
    if (beaconIds.isEmpty) return Future.value(const {});
    return _repository.unreadForBeacons(beaconIds);
  }

  Future<void> fetchNextPage() async {
    if (_accountId.isEmpty) return;
    final current = snapshot.pages[snapshot.activeView];
    final cursor = current?.nextCursor;
    if (cursor == null || cursor.isEmpty) return;
    final generation = _accountGeneration;
    final feed = await _repository.fetch(
      view: snapshot.activeView,
      cursor: cursor,
      search: _search,
    );
    if (generation != _accountGeneration) return;
    _applyPage(feed, replaceHead: false);
  }

  Future<void> markSeen(Iterable<String> ids) async {
    final pending = ids.toSet();
    if (pending.isEmpty) return;
    final generation = _accountGeneration;
    final unreadDelta = _displayedUnreadCount(pending);
    final token = _acks.markSeen(pending);
    _applyOptimisticAcks(unreadDelta: -unreadDelta);
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
      }
      _logger.warning('Attention mark-seen failed', error, stackTrace);
      rethrow;
    }
    if (generation == _accountGeneration) unawaited(_requestHeadRefresh());
  }

  Future<void> markUnseen(Iterable<String> ids) async {
    final pending = ids.toSet();
    if (pending.isEmpty) return;
    final generation = _accountGeneration;
    final unreadDelta = _displayedSeenCount(pending);
    final token = _acks.markUnseen(pending);
    _applyOptimisticAcks(unreadDelta: unreadDelta);
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
          return;
        }
        _acks.markCommitted(still, token);
      });
    } catch (error, stackTrace) {
      if (generation == _accountGeneration) {
        _acks.discard(pending, token: token);
        _applyOptimisticAcks(unreadDelta: -unreadDelta);
      }
      _logger.warning('Attention mark-unseen failed', error, stackTrace);
      rethrow;
    }
    if (generation == _accountGeneration) unawaited(_requestHeadRefresh());
  }

  Future<void> markAllSeen() async {
    final ids = _receiptsById.values
        .where((receipt) => !_displaysSeen(receipt.id))
        .map((receipt) => receipt.id)
        .toSet();
    final generation = _accountGeneration;
    final previousUnread = snapshot.summary.unreadTotal;
    final token = _acks.markAllSeen(ids);
    _applyOptimisticAcks(unreadTotal: 0);
    final previous = _markAllSeenChain;
    final op = previous.catchError((_) {}).then((_) async {
      await Future.wait([
        for (final chain in _ackChains.values) chain.catchError((_) {}),
      ]);
      if (generation != _accountGeneration) return;
      try {
        await _repository.markAllSeen();
        if (generation != _accountGeneration) return;
        _acks.markCommitted(ids, token);
      } catch (error, stackTrace) {
        if (generation == _accountGeneration) {
          _acks.discard(ids, token: token);
          _applyOptimisticAcks(unreadTotal: previousUnread);
        }
        _logger.warning('Attention mark-all-seen failed', error, stackTrace);
        rethrow;
      }
    });
    _markAllSeenChain = op.catchError((_) {});
    await op;
    if (generation == _accountGeneration) unawaited(_requestHeadRefresh());
  }

  Future<void> settle(String receiptId) async {
    final receipt = _receiptsById[receiptId];
    if (receipt == null || !receipt.isLiveObligation) return;
    await _repository.settle(receiptId: receiptId, kind: 'resolved');
    await _requestHeadRefresh();
  }

  Future<void> _requestHeadRefresh() async {
    if (_accountId.isEmpty) return;
    if (_headRefreshInFlight) {
      _headRefreshQueued = true;
      return;
    }
    _headRefreshInFlight = true;
    final generation = _accountGeneration;
    try {
      final feed = await _repository.fetch(
        view: snapshot.activeView,
        search: _search,
      );
      if (generation == _accountGeneration) _applyPage(feed, replaceHead: true);
    } catch (error, stackTrace) {
      if (generation == _accountGeneration) {
        _emit(snapshot.copyWith(headRefreshError: error));
        _logger.warning('Attention head refresh failed', error, stackTrace);
      }
    } finally {
      _headRefreshInFlight = false;
      if (_headRefreshQueued) {
        _headRefreshQueued = false;
        unawaited(_requestHeadRefresh());
      }
    }
  }

  void _applyPage(AttentionFeed feed, {required bool replaceHead}) {
    final view = snapshot.activeView;
    final oldPage = snapshot.pages[view];
    for (final receipt in feed.page.items) {
      _receiptsById[receipt.id] = receipt;
    }
    // A reconnect can replay an already-normalized GraphQL list entry. Receipt
    // id is the feed's stable identity, so never project a repeated entry into
    // the UI even when the transport response contains one.
    final incoming = _uniqueByReceiptId(
      feed.page.items.map(_acks.apply),
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
    final pages = Map<AttentionView, AttentionFeedPage>.from(snapshot.pages)
      ..[view] = AttentionFeedPage(
        items: items,
        nextCursor: feed.page.nextCursor,
      );
    _emit(
      snapshot.copyWith(
        summary: feed.summary.copyWith(
          unreadTotal: math.max(
            0,
            feed.summary.unreadTotal + _acks.pendingUnreadDelta(_receiptsById),
          ),
        ),
        pages: pages,
        headRefreshError: null,
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

  void _applyOptimisticAcks({int unreadDelta = 0, int? unreadTotal}) {
    final pages = <AttentionView, AttentionFeedPage>{
      for (final entry in snapshot.pages.entries)
        entry.key: entry.value.copyWith(
          items: [
            for (final receipt in entry.value.items)
              _acks.apply(_receiptsById[receipt.id] ?? receipt),
          ].where((receipt) {
            if (entry.key != AttentionView.unread) return true;
            return !receipt.isSeen;
          }).toList(growable: false),
        ),
    };
    final unread = math.max(
      0,
      unreadTotal ?? snapshot.summary.unreadTotal + unreadDelta,
    );
    _emit(
      snapshot.copyWith(
        summary: snapshot.summary.copyWith(unreadTotal: unread),
        pages: pages,
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
  }
}
