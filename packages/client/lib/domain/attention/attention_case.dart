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
import 'attention_dismissible_membership.dart';
import 'attention_clear_store.dart';
import 'attention_group_projection.dart';
import 'entity/activity_beacon_attention.dart';
import 'entity/activity_offer_beacon_meta.dart';
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
  static const _maxIdsPerQuery = 500;
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

  /// Requests whose projections a **projection owner** outside this case (My
  /// Desk cards, the Activity pinned zone) must re-read. The case owns
  /// attention state; it does not own those screens' rows, so a move or an
  /// outcome is announced here rather than guessed at by each screen.
  final _requestInvalidations = StreamController<String>.broadcast();

  /// The Activity pinned zone's per-Request events, owned here. The raw
  /// server rows are kept so the projection can be re-derived whenever a
  /// child is dismissed or read; the zone itself holds no second copy (§0.3).
  final Map<String, ActivityOfferSortRow> _offerRowsByBeaconId = {};
  final _offerGroups =
      BehaviorSubject<Map<String, ActivityOfferBeaconMeta>>.seeded(
        const <String, ActivityOfferBeaconMeta>{},
      );

  /// Children carried inside a grouped row's `eventsPreview`. They are kept
  /// apart from [_receiptsById] on purpose: a child is addressable (a × can
  /// clear it, a delta can be attributed to its surface) but it is not a
  /// top-level feed row, so it must never widen a sweep's membership or the
  /// page-level unread arithmetic.
  final Map<String, AttentionReceipt> _childReceiptsById = {};

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

  /// Bumped every time a reconcile adopts an authoritative summary.
  ///
  /// An optimistic operation that started before the adoption may not post
  /// its compensating totals afterwards: its overlay is already gone, so the
  /// delta would land on the server's numbers instead of on its own.
  int _adoptionSerial = 0;
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

  Stream<String> get requestInvalidations => _requestInvalidations.stream;

  Stream<Map<String, ActivityOfferBeaconMeta>> get activityOfferGroups =>
      _offerGroups.stream;

  Map<String, ActivityOfferBeaconMeta> get activityOfferGroupsSnapshot =>
      _offerGroups.value;

  AttentionSurfaceSummary get surfaceSummarySnapshot =>
      _surfaceSummarySubject.value;

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
          // A Request can change hands, and with it the surface it belongs
          // to. That is a beacon-level fact, not a receipt-level one (D14).
          RealtimeEntityKind.beacon,
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
    switch (change.kind) {
      case RealtimeEntityKind.beacon:
      case RealtimeEntityKind.helpOffer:
      case RealtimeEntityKind.inboxItem:
        // R5 — one transition, one generation. Help-offer and Inbox changes
        // used to refresh the counters and the Activity page independently,
        // and even the beacon path announced the Request to My Desk *before*
        // committing For You. Responsibility can flip either way on any of
        // these three, so all three take the same coordinated route.
        unawaited(_transitionAcrossSurfaces(change.aggregateId));
      // The remaining subscribed kind is `notification`; a `default` keeps
      // this exhaustive if the subscription set ever widens.
      // ignore: no_default_cases
      default:
        // Clear state and outcome generation arrive as notification hints;
        // the affected Request rides on the NOTIFY extras, which name it on
        // `childId` rather than `aggregateId`.
        //
        // U15R-d: the same coordinated route as the other three. This one
        // used to announce the Request and refresh the counters and the feed
        // heads in three independent steps, so My Desk could pick it up while
        // For You was still holding the old page — the state D14 forbids, on
        // the one kind R5's brief did not name.
        unawaited(_transitionAcrossSurfaces(change.childId));
    }
  }

  /// One Request's move across surfaces, start to finish.
  ///
  /// The announcement is the **last** step, not the first. My Desk is a
  /// separate projection with its own fetch, so telling it first let it
  /// re-read while For You was still holding the old page — the Request
  /// visible on two surfaces at once, which is exactly the state D14 forbids
  /// and exactly what the U15 test claimed to rule out while observing only
  /// My Desk's own two lists (R5).
  Future<void> _transitionAcrossSurfaces(String? beaconId) async {
    // One in flight, one rerun — the same discipline the head refresher has
    // always applied, and load-bearing since U15R-d put `notification` on
    // this route: a burst of twenty NOTIFY hints must not become twenty
    // coordinated refreshes. The rerun covers every Request named while the
    // first was in flight, so coalescing never loses an announcement.
    if (_transitionInFlight) {
      _transitionQueued = true;
      if (beaconId != null && beaconId.isNotEmpty) {
        _transitionQueuedBeaconIds.add(beaconId);
      }
      return;
    }
    _transitionInFlight = true;
    var beaconIds = <String>{
      if (beaconId != null && beaconId.isNotEmpty) beaconId,
    };
    try {
      do {
        _transitionQueued = false;
        await _refreshAcrossSurfaces();
        // Announced whatever the refresh did — including when it declined to
        // run because nothing is signed in or attached. A projection that
        // never hears about the move is worse than one that hears late.
        for (final id in beaconIds) {
          _invalidateRequest(id);
        }
        beaconIds = {..._transitionQueuedBeaconIds};
        _transitionQueuedBeaconIds.clear();
      } while (_transitionQueued);
    } finally {
      _transitionInFlight = false;
    }
  }

  bool _transitionInFlight = false;
  bool _transitionQueued = false;
  final _transitionQueuedBeaconIds = <String>{};

  void _invalidateRequest(String? beaconId) {
    if (beaconId == null || beaconId.isEmpty) return;
    if (_requestInvalidations.isClosed) return;
    _requestInvalidations.add(beaconId);
  }

  /// Re-reads every attached feed destination **and** the surface summary,
  /// then commits them in one synchronous move.
  ///
  /// Doing it in two steps is what would produce the state D14 forbids: a
  /// moment where the Request is still on the old surface and already counted
  /// on the new one, or gone from one and not yet in the other.
  Future<void> _refreshAcrossSurfaces() async {
    if (_accountId.isEmpty) return;
    final destinations = _feedSessions.attachedDestinationIds.toList(
      growable: false,
    );
    if (destinations.isEmpty) {
      unawaited(_requestSurfaceSummaryRefresh());
      _requestHeadRefreshForAllAttached();
      return;
    }
    final accountGeneration = _accountGeneration;
    final mutationSerial = _mutationSerial;
    final summarySerial = ++_surfaceSummaryRequestSerial;
    final requested = [
      for (final destinationId in destinations)
        (
          destinationId: destinationId,
          session: _feedSessions.session(destinationId),
        ),
    ];
    final summaryFuture = _repository.surfaceSummary();
    final pageFutures = [
      for (final request in requested)
        _repository.fetch(
          view: request.session.activeView,
          search: request.session.normalizedSearch,
          surface: surfaceForDestination(request.destinationId),
        ),
    ];
    final AttentionSurfaceSummary summary;
    final List<AttentionFeed> feeds;
    try {
      summary = await summaryFuture;
      feeds = await Future.wait(pageFutures);
    } catch (error, stackTrace) {
      _logger.warning('Attention surface move refresh failed', error, stackTrace);
      return;
    }
    if (accountGeneration != _accountGeneration) return;
    if (mutationSerial != _mutationSerial) return;
    if (summarySerial != _surfaceSummaryRequestSerial) return;
    final next = <String, AttentionFeedSession>{};
    AttentionSummary? feedSummary;
    for (var i = 0; i < requested.length; i++) {
      final request = requested[i];
      final landed = _feedSessions.session(request.destinationId);
      if (landed.requestGeneration != request.session.requestGeneration) {
        continue;
      }
      next[request.destinationId] = _composePage(
        landed,
        feeds[i],
        view: request.session.activeView,
        replaceHead: true,
      );
      feedSummary ??= feeds[i].summary;
    }
    _feedSessions.updateAll(next);
    if (!_surfaceSummarySubject.isClosed) {
      _surfaceSummarySubject.add(summary);
    }
    if (feedSummary != null) _emitFeedSummary(feedSummary);
  }

  void _onAccountChanged(String accountId) {
    if (accountId == _accountId) return;
    _accountId = accountId;
    _accountGeneration++;
    _headRefreshQueued.clear();
    _headRefreshInFlight.clear();
    _receiptsById.clear();
    _childReceiptsById.clear();
    _offerRowsByBeaconId.clear();
    if (!_offerGroups.isClosed) {
      _offerGroups.add(const <String, ActivityOfferBeaconMeta>{});
    }
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
  }) async {
    final page = await _repository.activityOffers(cursor: cursor, limit: limit);
    // A head load replaces the zone; a tail load extends it.
    if (cursor == null || cursor.isEmpty) _offerRowsByBeaconId.clear();
    for (final row in page.items) {
      _offerRowsByBeaconId[row.beaconId] = row;
    }
    _indexChildren([for (final row in page.items) ...row.eventsPreview]);
    _publishOfferGroups();
    return page;
  }

  /// The zone's total, without disturbing the loaded rows.
  Future<int> activityOffersCount() async =>
      (await _repository.activityOffers(limit: 1)).totalCount;

  /// Drops one Request from the zone — it is no longer an open forward.
  void forgetOfferGroup(String beaconId) {
    if (_offerRowsByBeaconId.remove(beaconId) == null) return;
    _publishOfferGroups();
  }

  /// Unseen Requests, answered from the owned projections first and only
  /// then from the server, for ids the zone has never seen.
  Future<Set<String>> unseenForBeacons(Set<String> beaconIds) async {
    if (beaconIds.isEmpty) return const {};
    final groups = _offerGroups.value;
    final unseen = <String>{
      for (final id in beaconIds)
        if (groups[id]?.unseen ?? false) id,
    };
    final unknown = <String>[
      for (final id in beaconIds)
        if (!groups.containsKey(id)) id,
    ];
    if (unknown.isEmpty) return unseen;
    for (var offset = 0; offset < unknown.length; offset += _maxIdsPerQuery) {
      final next = offset + _maxIdsPerQuery;
      final end = next < unknown.length ? next : unknown.length;
      unseen.addAll(
        await _repository.unreadForBeacons(unknown.sublist(offset, end).toSet()),
      );
    }
    return unseen;
  }

  void _publishOfferGroups() {
    if (_offerGroups.isClosed) return;
    _offerGroups.add({
      for (final entry in _offerRowsByBeaconId.entries)
        entry.key: _projectOfferRow(entry.value),
    });
  }

  ActivityOfferBeaconMeta _projectOfferRow(ActivityOfferSortRow row) {
    final projected = projectAttentionGroup(
      eventTotal: row.eventTotal,
      eventUnseenCount: row.eventUnseenCount,
      eventsPreview: row.eventsPreview,
      unseen: row.unseen,
      overlay: (child) => _overlay(_childReceiptsById[child.id] ?? child),
    );
    return ActivityOfferBeaconMeta(
      eventTotal: projected.eventTotal,
      eventUnseenCount: projected.eventUnseenCount,
      eventsPreview: projected.eventsPreview,
      unseen: projected.unseen,
    );
  }

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
    // R2/D02 — a read moves the **read** axis and nothing else. Every total
    // below this line (`unreadTotal`, `activityUnreadTotal`,
    // `myWorkUnreadTotal`) is defined by the server as *active attention*:
    // `NOT requires_action AND cleared_at IS NULL`, union live obligations.
    // `seen_at` is not in any of them, so a read must not move them.
    final token = _acks.markSeen(pending);
    _applyOptimisticAcks();
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
        _applyOptimisticAcks();
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
    // The read axis, both ways (R2/D02).
    final token = _acks.markUnseen(pending);
    _applyOptimisticAcks();
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
          _applyOptimisticAcks();
          return;
        }
        _acks.markCommitted(still, token);
      });
    } catch (error, stackTrace) {
      if (generation == _accountGeneration) {
        _acks.discard(pending, token: token);
        _applyOptimisticAcks();
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
    // Reaching the bottom of a discussion is reading, not clearing (§4).
    final token = pending.isEmpty
        ? null
        : _acks.markSeen(pending);
    if (token != null) {
      _applyOptimisticAcks();
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
        _applyOptimisticAcks();
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
    final token = _acks.markAllSeen(ids);
    // R2 — "Read all" used to zero the surface totals. It never cleared
    // anything: the rows it touched still carry uncleared optional attention,
    // and the server keeps counting them. Zeroing here announced a sweep the
    // user did not ask for and did not get.
    _applyOptimisticAcks();
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
          _applyOptimisticAcks();
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

  /// «Очистить всё» on one Request's card (§6.2, E25): the same watermark
  /// capture as [clearRequestOpen], but with the `explicit` reason, because
  /// the user pressed a button rather than opened the Request. Undoable under
  /// its operation id like every other capture (E10, D13).
  Future<AttentionClearResult> clearBeacon({
    required String beaconId,
  }) => _clear(
    kind: AttentionClearCaptureKind.explicit,
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
        _invalidateRequest(
          beaconId ?? (receiptId == null ? null : _knownReceipt(receiptId)?.beaconId),
        );
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
    // Top-level rows only: a child inside a preview is not an independent
    // sweep member, and counting it would decrement a surface twice.
    //
    // R2 — and only rows that are genuinely dismissible. Owner decision A is
    // a guarantee about what the user *sees*, so it has to hold in the
    // optimistic frame, not just once the server has refused.
    final loaded = optimisticSweepMembers(_receiptsById.values.map(_overlay));
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
      // D15 step 6 — *replace* the cached indicators, do not merge them.
      //
      // Everything the client holds that the server did not say is withdrawn
      // first: the read-axis acks and the clear-axis operation overlays. A
      // surviving overlay would re-hide a row the repair says is live, and an
      // operation still in flight would post its compensating delta onto the
      // adopted totals afterwards — which is why [_adoptionSerial] moves here
      // and `_applyClearOptimistically` checks it before compensating.
      //
      // What is *not* replaced: nothing local is erased. Optional clear
      // state, Inbox stance, source actions and History all live on the
      // server and come back in the summary and the refetched heads.
      _acks.discardAllPending();
      _clears.discardAllPending();
      _adoptionSerial++;
      // Re-projects every attached page from the server-truth mirror with no
      // overlay left to stamp on it. The zero delta is the point: no total is
      // adjusted here, only the projection is rebuilt.
      _applyOptimisticAcks();
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
    final adoption = _adoptionSerial;
    // R2 — a clear delta is made of **active optional membership**, not of
    // what happens to look unread. A receipt the user already read still
    // counts on every server total until it is cleared, so clearing it is
    // exactly the moment those totals move.
    final deltas = _surfaceActiveOptionalDeltas(members);
    final unreadDelta = _activeOptionalCount(members);
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
      // A reconcile has since replaced the indicators this operation was
      // optimistic about (D15 step 6). Its overlay is gone and its deltas are
      // no longer relative to anything the client holds.
      if (adoption != _adoptionSerial) return result;
      final applied = appliedIdsOf(result).toSet();
      // Only the members the server says it applied survive. A skipped, a
      // denied and an unanswered (still pending) member are all rolled back —
      // `partial` is not a slow `complete`.
      final withdrawn = members.difference(applied);
      _clears.commit(operationId, applied);
      if (withdrawn.isNotEmpty) {
        final restored = _surfaceActiveOptionalDeltas(withdrawn);
        _applyOptimisticSurfaceSummary(
          activityUnreadDelta: restored.activity,
          myWorkUnreadDelta: restored.myWork,
        );
      }
      _applyOptimisticAcks(
        unreadDelta: withdrawn.isEmpty ? 0 : _activeOptionalCount(withdrawn),
      );
      return result;
    } catch (error, stackTrace) {
      if (generation == _accountGeneration &&
          adoption == _adoptionSerial &&
          members.isNotEmpty) {
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
    _feedSessions.update(
      destinationId,
      _composePage(session, feed, view: view, replaceHead: replaceHead),
    );
    _emitFeedSummary(feed.summary);
    if (replaceHead) {
      _recordQaHeadRefreshLatency(
        _feedSessions.session(destinationId).pages[view]?.items ?? const [],
        DateTime.now().toUtc(),
      );
    }
  }

  /// Builds the next session for one destination **without** committing it,
  /// so several destinations can be committed together.
  AttentionFeedSession _composePage(
    AttentionFeedSession session,
    AttentionFeed feed, {
    required AttentionView view,
    required bool replaceHead,
  }) {
    final oldPage = session.pages[view];
    for (final receipt in feed.page.items) {
      _receiptsById[receipt.id] = receipt;
    }
    _indexChildren(feed.page.items);
    final incoming = _uniqueByRequestIdentity(
      feed.page.items.map(_project),
    );
    final items = replaceHead
        ? incoming
        : _uniqueByRequestIdentity([...?oldPage?.items, ...incoming]);
    final pages = Map<AttentionView, AttentionFeedPage>.from(session.pages)
      ..[view] = AttentionFeedPage(
        items: items,
        nextCursor: feed.page.nextCursor,
      );
    return session.copyWith(
      pages: pages,
      headRefreshError: null,
    );
  }

  void _emitFeedSummary(AttentionSummary summary) {
    // U17b/§3 — `unreadTotal` is the server's **active attention** total
    // (`NOT requires_action AND cleared_at IS NULL`, union live obligations),
    // not a count of unread rows. A pending read-axis ack is therefore not a
    // delta on it: folding one in made History's own "mark unread" raise the
    // badge for a row that had already been cleared, which is exactly the
    // resurrection §3 forbids. The server's number is emitted as given.
    _emit(snapshot.copyWith(summary: summary));
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

  /// Every receipt this client can address — top-level rows and the children
  /// indexed out of grouped previews.
  AttentionReceipt? _knownReceipt(String id) =>
      _receiptsById[id] ?? _childReceiptsById[id];

  @visibleForTesting
  bool knowsReceipt(String id) => _knownReceipt(id) != null;

  /// The local view of one receipt: the clear axis, then the read axis.
  AttentionReceipt _overlay(AttentionReceipt receipt) =>
      _clears.apply(_acks.apply(receipt));

  /// [_overlay], plus the grouped row's own preview and counts re-derived
  /// from its children.
  AttentionReceipt _project(AttentionReceipt receipt) {
    final overlaid = _overlay(receipt);
    if (overlaid.eventsPreview.isEmpty) return overlaid;
    final projected = projectAttentionGroup(
      eventTotal: overlaid.eventTotal ?? overlaid.eventsPreview.length,
      eventUnseenCount: overlaid.eventUnseenCount ?? 0,
      eventsPreview: overlaid.eventsPreview,
      unseen: false,
      overlay: (child) => _overlay(_childReceiptsById[child.id] ?? child),
    );
    var next = overlaid.copyWith(eventsPreview: projected.eventsPreview);
    if (overlaid.eventTotal != null) {
      next = next.copyWith(eventTotal: projected.eventTotal);
    }
    if (overlaid.eventUnseenCount != null) {
      next = next.copyWith(eventUnseenCount: projected.eventUnseenCount);
    }
    return next;
  }

  void _indexChildren(Iterable<AttentionReceipt> items) {
    for (final receipt in items) {
      for (final child in receipt.eventsPreview) {
        _childReceiptsById[child.id] = child;
      }
    }
  }

  bool _displaysSeen(String id) {
    if (_acks.isOptimisticallyUnseen(id)) return false;
    if (_acks.isOptimisticallySeen(id)) return true;
    return _knownReceipt(id)?.isSeen ?? false;
  }



  /// Active optional attention among [ids] — the clear axis (`activeOptional`
  /// in the server's SQL), deliberately blind to `seenAt`.
  int _activeOptionalCount(Iterable<String> ids) {
    var n = 0;
    for (final id in ids) {
      final receipt = _knownReceipt(id);
      if (receipt != null && isActiveOptional(_overlay(receipt))) n++;
    }
    return n;
  }

  ({int activity, int myWork}) _surfaceActiveOptionalDeltas(
    Iterable<String> ids,
  ) {
    var activity = 0;
    var myWork = 0;
    for (final id in ids) {
      final receipt = _knownReceipt(id);
      if (receipt == null) continue;
      if (!isActiveOptional(_overlay(receipt))) continue;
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
                _project(_receiptsById[receipt.id] ?? receipt),
            ].where((receipt) {
              // R2 — the `unread` view is the server's *active attention*
              // view (`$2 = 'unread' AND is_active_attention`), not a read
              // list. Reading a row must not take it off the list the server
              // still returns; clearing it is what does. R10 — and
              // `is_active_attention` is not one expression: each item kind
              // has its own, so the mirror is keyed on the kind.
              if (entry.key != AttentionView.unread) return true;
              return isInUnreadView(receipt);
            }).toList(growable: false),
          ),
      };
      _feedSessions.update(destinationId, session.copyWith(pages: pages));
    }
    _publishOfferGroups();
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

  /// The key a merged page is unique by.
  ///
  /// A **grouped** row is one card for one Request, so its identity is the
  /// Request -- not the row id, which the server is free to re-mint when the
  /// group's sort key moves. An ungrouped receipt is its own event: two of
  /// them may share a `beaconId` and must keep separate rows.
  static String _requestIdentity(AttentionReceipt receipt) {
    final beaconId = receipt.beaconId;
    if (beaconId == null || beaconId.isEmpty) return 'receipt:${receipt.id}';
    return switch (receipt.itemKind) {
      AttentionItemKind.forward ||
      AttentionItemKind.watchingDigest ||
      AttentionItemKind.requestActivity => 'request:'
          '${receipt.itemKind.wireName}:$beaconId',
      AttentionItemKind.receipt => 'receipt:${receipt.id}',
    };
  }

  /// Merges keeping the **first** position and the **last** payload: a moved
  /// group does not jump under the user, and the fresher copy wins.
  ///
  /// U10c proved the server's failure shape is a vanish -- head and tail are
  /// independent queries -- so a client that only suppressed repeats would
  /// still be wrong in the other direction. Nothing is dropped here that was
  /// not already present under the same identity.
  List<AttentionReceipt> _uniqueByRequestIdentity(
    Iterable<AttentionReceipt> items,
  ) =>
      items
          .fold<Map<String, AttentionReceipt>>(
            {},
            (byIdentity, receipt) =>
                byIdentity..[_requestIdentity(receipt)] = receipt,
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
    await _requestInvalidations.close();
    await _offerGroups.close();
    await _snapshot.close();
    await _surfaceSummarySubject.close();
  }
}
