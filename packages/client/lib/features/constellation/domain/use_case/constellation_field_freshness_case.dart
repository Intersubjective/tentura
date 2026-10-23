import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/clock_port.dart';
import 'package:tentura/domain/port/wake_up_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/features/like/domain/port/person_trust_writes_port.dart';

import '../constellation_field_patches.dart';
import '../entity/constellation_field.dart';
import '../port/constellation_targeted_read_port.dart';
import 'constellation_field_store_case.dart';

/// Keeps an open field fresh between FULL reads without adding any (#672,
/// #671). The global `constellation_field` hint stays on its lazy D8 window;
/// these paths only touch what one viewer can see change:
///
/// * the viewer's own acknowledged trust writes are patched in at once, no
///   read;
/// * a `relationship` hint naming someone on the field reads the viewer's
///   explicit trust to and from just those people (one small read per burst,
///   only `vote_user`) and patches it in;
/// * a `constellation_item` hint (a direct contact published a discoverable
///   Request) fetches just that Request through the authorized read and adds
///   it when its author is on the field inside the visible set.
///
/// While the field is hidden nothing is read: the store refreshes once when
/// it is shown again.
@Order(3)
@singleton
final class ConstellationFieldFreshnessCase extends UseCaseBase {
  ConstellationFieldFreshnessCase(
    this._store,
    this._reads,
    PersonTrustWritesPort trustWrites,
    RealtimeSyncCase realtime,
    this._wakeUp,
    this._clock, {
    required super.env,
    required super.logger,
  }) {
    _subscriptions = [
      trustWrites.personTrustWrites.listen(_onOwnTrust),
      realtime
          .changesFor(const {RealtimeEntityKind.relationship})
          .listen(_onRelationship),
      realtime
          .changesFor(const {RealtimeEntityKind.constellationItem})
          .listen(_onItem),
    ];
  }

  final ConstellationFieldStoreCase _store;
  final ConstellationTargetedReadPort _reads;
  final WakeUpPort _wakeUp;
  final ClockPort _clock;
  late final List<StreamSubscription<Object?>> _subscriptions;

  /// Hints of one burst share a read; a steady stream cannot postpone it.
  static const batchWindow = Duration(milliseconds: 250);

  /// More people named in one burst than this is a bulk change (a full trust
  /// recompute): left to the lazy FULL.
  static const maxRelationIdsPerBurst =
      2 * ConstellationTargetedReadPort.maxRelationIds;

  /// An own write acknowledged this recently explains a hint about the
  /// viewer's own trust change; an older one means another session made it.
  static const ownEchoWindow = Duration(seconds: 5);

  final _pendingRelationIds = <String>{};
  var _ownChangeElsewhere = false;
  DateTime? _lastOwnAckAt;
  final _pendingRequestIds = <String>{};
  WakeUpHandle? _timer;
  Future<void>? _inFlight;

  @disposeMethod
  Future<void> dispose() async {
    _timer?.cancel();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
  }

  void _onOwnTrust(PersonTrustWrite write) {
    _lastOwnAckAt = _clock.now();
    _store.applyOwnTrust(write.personId, trusts: write.amount > 0);
  }

  void _onRelationship(RealtimeEntityChange change) {
    final viewerId = _store.accountId;
    final field = _store.current.field;
    if (viewerId.isEmpty || field == null) return;
    // The hint names one endpoint and the account that made the change; an
    // edge to the viewer has the viewer as the other endpoint.
    final named = {change.aggregateId, ?change.actorUserId}..remove(viewerId);
    if (named.isEmpty) {
      // The viewer changed trust toward someone who sorts after them: the
      // hint names only the viewer. This session's own writes are patched on
      // their acknowledgement; one made in another session needs a read.
      if (change.actorUserId == viewerId) {
        _ownChangeElsewhere = true;
        _schedule();
      }
      return;
    }
    final onField = [
      for (final id in named)
        if (constellationFieldHasPerson(field, id)) id,
    ];
    if (onField.isEmpty) return;
    if (!_store.canFetch) {
      unawaited(_store.requestRefresh(ConstellationRefreshReason.realtime));
      return;
    }
    _pendingRelationIds.addAll(onField);
    _schedule();
  }

  void _onItem(RealtimeEntityChange change) {
    final viewerId = _store.accountId;
    final field = _store.current.field;
    if (viewerId.isEmpty ||
        field == null ||
        change.operation != RealtimeOperation.insert ||
        _hasBeacon(field, change.aggregateId)) {
      return;
    }
    // Only an author inside the viewer's visible set has Requests on the
    // field; anyone else's is not worth a read.
    final actor = change.actorUserId;
    if (actor != null &&
        actor != viewerId &&
        !constellationFieldHasVisiblePerson(field, actor)) {
      return;
    }
    if (!_store.canFetch) {
      unawaited(_store.requestRefresh(ConstellationRefreshReason.realtime));
      return;
    }
    _pendingRequestIds.add(change.aggregateId);
    _schedule();
  }

  void _schedule() {
    if (_timer != null || _inFlight != null) return;
    _timer = _wakeUp.schedule(batchWindow, () {
      _timer = null;
      unawaited(
        _inFlight = _drain().whenComplete(() {
          _inFlight = null;
          if (_pendingRelationIds.isNotEmpty ||
              _pendingRequestIds.isNotEmpty ||
              _ownChangeElsewhere) {
            _schedule();
          }
        }),
      );
    });
  }

  Future<void> _drain() async {
    if (_ownChangeElsewhere) {
      _ownChangeElsewhere = false;
      final lastAck = _lastOwnAckAt;
      final echo =
          lastAck != null &&
          _clock.now().difference(lastAck).abs() <= ownEchoWindow;
      if (!echo) {
        // Who it was is unknown: one FULL for this viewer, as after a write
        // to someone not on the field.
        unawaited(_store.requestRefresh(ConstellationRefreshReason.realtime));
      }
    }
    if (!_store.canFetch) {
      if (_pendingRelationIds.isNotEmpty || _pendingRequestIds.isNotEmpty) {
        unawaited(_store.requestRefresh(ConstellationRefreshReason.realtime));
      }
      _pendingRelationIds.clear();
      _pendingRequestIds.clear();
      return;
    }
    if (_pendingRelationIds.isNotEmpty) {
      final ids = _pendingRelationIds.toList();
      _pendingRelationIds.clear();
      if (ids.length > maxRelationIdsPerBurst) {
        logger.fine(
          'Field freshness: ${ids.length} people changed at once; '
          'left to the lazy refresh',
        );
      } else {
        for (var i = 0; i < ids.length; i += _relationChunk) {
          await _readRelations(ids.skip(i).take(_relationChunk).toSet());
        }
      }
    }
    if (_pendingRequestIds.isNotEmpty) {
      final ids = _pendingRequestIds
          .take(ConstellationTargetedReadPort.maxRequestIds)
          .toSet();
      _pendingRequestIds.removeAll(ids);
      await _fetchRequests(ids);
    }
  }

  static const _relationChunk = ConstellationTargetedReadPort.maxRelationIds;

  Future<void> _readRelations(Set<String> ids) async {
    final mark = _store.readMark();
    try {
      final relations = await _reads.readViewerRelations(ids);
      _store.applyRelations(relations, mark);
    } on Object catch (error, stackTrace) {
      logger.warning('Field relation read failed', error, stackTrace);
    }
  }

  Future<void> _fetchRequests(Set<String> ids) async {
    final mark = _store.readMark();
    try {
      final requests = await _reads.fetchRequests(
        ids,
        membershipFilters: _store.projectionParams.membershipFilters,
      );
      final field = _store.current.field;
      if (field == null) return;
      _store.addRequests([
        for (final request in requests)
          if (request.isMine ||
              constellationFieldHasVisiblePerson(field, request.authorId))
            request,
      ], mark);
    } on Object catch (error, stackTrace) {
      logger.warning('Field Request read failed', error, stackTrace);
    }
  }

  static bool _hasBeacon(ConstellationField field, String beaconId) =>
      field.requests.any((r) => r.id == beaconId) ||
      field.posts.any((p) => p.id == beaconId) ||
      field.resolvedAnchorProjection.pinnedRequests.any(
        (r) => r.id == beaconId,
      );
}
