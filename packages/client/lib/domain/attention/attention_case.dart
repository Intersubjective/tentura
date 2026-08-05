import 'dart:async';

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
    _acks.markSeen(pending);
    _applyOptimisticAcks();
    try {
      await _repository.markSeen(pending.toList(growable: false));
    } catch (error, stackTrace) {
      if (generation == _accountGeneration) {
        _acks.discard(pending);
        _applyOptimisticAcks();
      }
      _logger.warning('Attention mark-seen failed', error, stackTrace);
      rethrow;
    }
    if (generation == _accountGeneration) unawaited(_requestHeadRefresh());
  }

  Future<void> markAllSeen() async {
    final ids = _receiptsById.values
        .where((receipt) => !receipt.isSeen)
        .map((receipt) => receipt.id)
        .toSet();
    final generation = _accountGeneration;
    _acks.markAllSeen(ids);
    _applyOptimisticAcks();
    try {
      await _repository.markAllSeen();
    } catch (error, stackTrace) {
      if (generation == _accountGeneration) {
        _acks.discard(ids);
        _applyOptimisticAcks();
      }
      _logger.warning('Attention mark-all-seen failed', error, stackTrace);
      rethrow;
    }
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
    final incoming = feed.page.items.map(_acks.apply).toList(growable: false);
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
    _emit(snapshot.copyWith(summary: feed.summary, pages: pages, headRefreshError: null));
    if (replaceHead) {
      _recordQaHeadRefreshLatency(items, DateTime.now().toUtc());
    }
  }

  void _applyOptimisticAcks() {
    final pages = <AttentionView, AttentionFeedPage>{
      for (final entry in snapshot.pages.entries)
        entry.key: entry.value.copyWith(
          items: entry.value.items
              .map(
                (receipt) => _acks.apply(_receiptsById[receipt.id] ?? receipt),
              )
              .toList(growable: false),
        ),
    };
    final unread = _receiptsById.values
        .map(_acks.apply)
        .where((receipt) => !receipt.isSeen)
        .length;
    _emit(
      snapshot.copyWith(
        summary: snapshot.summary.copyWith(unreadTotal: unread),
        pages: pages,
      ),
    );
  }

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
