import 'dart:async';

import 'package:injectable/injectable.dart';
import 'package:logging/logging.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';

import 'attention_ack_store.dart';
import 'entity/attention_feed.dart';
import 'entity/attention_receipt.dart';
import 'entity/attention_summary.dart';
import 'port/attention_account_port.dart';
import 'port/attention_repository_port.dart';

/// The sole owner that converts notification hints into attention feed refreshes.
@lazySingleton
final class AttentionCase {
  AttentionCase(
    this._repository,
    this._account,
    this._realtime,
    this._env,
    this._logger,
  ) {
    if (_env.updatesTabEnabled) _start();
  }

  final AttentionRepositoryPort _repository;
  final AttentionAccountPort _account;
  final RealtimeSyncCase _realtime;
  final Env _env;
  final Logger _logger;
  final AttentionAckStore _acks = AttentionAckStore();
  final _snapshot = BehaviorSubject<AttentionFeedSnapshot>.seeded(
    const AttentionFeedSnapshot(),
  );
  final Map<String, AttentionReceipt> _receiptsById = {};

  StreamSubscription<String>? _accountSub;
  StreamSubscription<RealtimeEntityChange>? _notificationSub;
  StreamSubscription<RealtimeCatchUp>? _catchUpSub;
  String _accountId = '';
  int _accountGeneration = 0;
  bool _headRefreshInFlight = false;
  bool _headRefreshQueued = false;

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

  Future<void> refresh() async => _requestHeadRefresh();

  Future<void> fetchNextPage() async {
    if (!_env.updatesTabEnabled || _accountId.isEmpty) return;
    final current = snapshot.pages[snapshot.activeView];
    final cursor = current?.nextCursor;
    if (cursor == null || cursor.isEmpty) return;
    final generation = _accountGeneration;
    final feed = await _repository.fetch(
      view: snapshot.activeView,
      cursor: cursor,
    );
    if (generation != _accountGeneration) return;
    _applyPage(feed, replaceHead: false);
  }

  Future<void> markSeen(Iterable<String> ids) async {
    if (!_env.updatesTabEnabled) return;
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
    if (!_env.updatesTabEnabled) return;
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

  Future<void> _requestHeadRefresh() async {
    if (!_env.updatesTabEnabled || _accountId.isEmpty) return;
    if (_headRefreshInFlight) {
      _headRefreshQueued = true;
      return;
    }
    _headRefreshInFlight = true;
    final generation = _accountGeneration;
    try {
      final feed = await _repository.fetch(view: snapshot.activeView);
      if (generation == _accountGeneration) _applyPage(feed, replaceHead: true);
    } catch (error, stackTrace) {
      if (generation == _accountGeneration) {
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
    final incoming = feed.page.items.map(_acks.apply).toList(growable: false);
    for (final receipt in incoming) {
      _receiptsById[receipt.id] = receipt;
    }
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
    _emit(snapshot.copyWith(summary: feed.summary, pages: pages));
  }

  void _applyOptimisticAcks() {
    final pages = <AttentionView, AttentionFeedPage>{
      for (final entry in snapshot.pages.entries)
        entry.key: entry.value.copyWith(
          items: entry.value.items.map(_acks.apply).toList(growable: false),
        ),
    };
    for (final page in pages.values) {
      for (final receipt in page.items) {
        _receiptsById[receipt.id] = receipt;
      }
    }
    final unread = _receiptsById.values
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

  @disposeMethod
  Future<void> dispose() async {
    await _accountSub?.cancel();
    await _notificationSub?.cancel();
    await _catchUpSub?.cancel();
    await _snapshot.close();
  }
}
