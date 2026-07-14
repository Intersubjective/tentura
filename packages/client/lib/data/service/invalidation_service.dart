import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/data/service/remote_api_client/realtime_transport_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_watch.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';

import 'remote_api_service.dart';

/// Maps the V2 WebSocket wire protocol into the shared domain sync boundary.
///
/// Entity hints identify server-owned projections. They never carry derived
/// state, and bursts are coalesced by `(kind, aggregateId)` before consumers
/// refetch authoritative snapshots.
@singleton
class InvalidationService implements RealtimeSyncPort {
  InvalidationService(RemoteApiService remoteApiService) {
    _send = remoteApiService.webSocketSend;
    _messageSubscription = _subscribe(remoteApiService.webSocketMessages);
    _transportSubscription = remoteApiService.realtimeTransportStatus.listen(
      _onTransportStatus,
    );
  }

  /// Unit tests without [RemoteApiService] / WebSocket wiring.
  @visibleForTesting
  InvalidationService.forTesting(
    Stream<Map<String, dynamic>> messages, {
    Stream<RealtimeTransportStatus>? transportStatuses,
    void Function(Object message)? send,
  }) {
    _send = send ?? (_) {};
    _messageSubscription = _subscribe(messages);
    _transportSubscription =
        (transportStatuses ?? const Stream<RealtimeTransportStatus>.empty())
            .listen(_onTransportStatus);
  }

  static const _debounceWindow = Duration(milliseconds: 500);

  late final StreamSubscription<Map<String, dynamic>> _messageSubscription;
  late final StreamSubscription<RealtimeTransportStatus> _transportSubscription;
  late final void Function(Object message) _send;

  String? _activeAccountId;
  int _latestConnectionEpoch = 0;
  bool _hasAuthenticatedCurrentAccount = false;

  final _entityChangeController =
      StreamController<RealtimeEntityChange>.broadcast();
  final _catchUpController = StreamController<RealtimeCatchUp>.broadcast();
  final _connectionStatusSubject =
      BehaviorSubject<RealtimeConnectionStatus>.seeded(
        const RealtimeConnectionStatus(
          connectionEpoch: 0,
          phase: RealtimeConnectionPhase.unbound,
        ),
      );

  @override
  late final Stream<RealtimeEntityChange> entityChanges =
      _entityChangeController.stream
          .bufferTime(_debounceWindow)
          .where((batch) => batch.isNotEmpty)
          .expand(_deduplicateEntityChanges)
          .asBroadcastStream();

  @override
  late final Stream<RealtimeCatchUp> catchUps = _catchUpController.stream
      .bufferTime(_debounceWindow)
      .where((batch) => batch.isNotEmpty)
      .expand(_deduplicateCatchUps)
      .asBroadcastStream();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      _connectionStatusSubject.stream;

  /// Temporary compatibility stream for repositories migrating to [entityChanges].
  late final Stream<String> beaconInvalidations = entityChanges
      .where((change) => change.kind == RealtimeEntityKind.beacon)
      .map((change) => change.aggregateId)
      .asBroadcastStream();

  /// Temporary compatibility stream for repositories migrating to [entityChanges].
  late final Stream<String> helpOfferInvalidations = entityChanges
      .where((change) => change.kind == RealtimeEntityKind.helpOffer)
      .map((change) => change.aggregateId)
      .asBroadcastStream();

  /// Temporary compatibility stream for repositories migrating to [entityChanges].
  late final Stream<String> forwardInvalidations = entityChanges
      .where((change) => change.kind == RealtimeEntityKind.forward)
      .map((change) => change.aggregateId)
      .asBroadcastStream();

  /// Temporary compatibility stream for room repositories during migration.
  late final Stream<BeaconRoomInvalidation> beaconRoomInvalidations =
      entityChanges
          .map(_toBeaconRoomInvalidation)
          .whereType<BeaconRoomInvalidation>()
          .asBroadcastStream();

  /// Temporary compatibility stream for capability repositories.
  late final Stream<String> capabilityInvalidations = entityChanges
      .where((change) => change.kind == RealtimeEntityKind.capability)
      .map((change) => change.aggregateId)
      .asBroadcastStream();

  StreamSubscription<Map<String, dynamic>> _subscribe(
    Stream<Map<String, dynamic>> messages,
  ) => messages.listen(_onMessage);

  void _onMessage(Map<String, dynamic> message) {
    if (message['path'] != 'entity_changes') return;
    switch (message['type']) {
      case 'subscription':
        _onInvalidation(message);
      case 'control':
        _onServerControl(message);
    }
  }

  void _onInvalidation(Map<String, dynamic> message) {
    final payload = _normalizeJsonObject(message['payload']);
    if (payload == null) return;
    final id = payload['id'];
    final kind = _entityKindFromWire(payload['entity']);
    final operation = _operationFromWire(payload['event']);
    final actorUserId = payload['actor_user_id'];
    if (id is! String || id.isEmpty || kind == null || operation == null) {
      return;
    }
    if (actorUserId != null && actorUserId is! String) {
      return;
    }

    _entityChangeController.add(
      RealtimeEntityChange(
        kind: kind,
        aggregateId: id,
        operation: operation,
        source: RealtimeChangeSource.serverInvalidation,
        actorUserId: actorUserId as String?,
      ),
    );
  }

  void _onServerControl(Map<String, dynamic> message) {
    final payload = _normalizeJsonObject(message['payload']);
    if (payload == null || payload['intent'] != 'catch_up') return;
    final reason = switch (payload['reason']) {
      'pg_listener_recovered' => RealtimeCatchUpReason.pgListenerRecovered,
      'server_requested' ||
      'protocol_change' => RealtimeCatchUpReason.serverRequested,
      _ => null,
    };
    if (reason != null) requestCatchUp(reason);
  }

  void _onTransportStatus(RealtimeTransportStatus transportStatus) {
    if (transportStatus.connectionEpoch < _latestConnectionEpoch) return;

    final accountChanged =
        transportStatus.accountId != null &&
        transportStatus.accountId != _activeAccountId;
    if (transportStatus.connectionEpoch > _latestConnectionEpoch) {
      _latestConnectionEpoch = transportStatus.connectionEpoch;
    }
    if (transportStatus.phase == RealtimeTransportPhase.unbound) {
      _activeAccountId = null;
      _hasAuthenticatedCurrentAccount = false;
    } else if (accountChanged) {
      _activeAccountId = transportStatus.accountId;
      _hasAuthenticatedCurrentAccount = false;
    }

    final status = RealtimeConnectionStatus(
      accountId: transportStatus.accountId,
      connectionEpoch: transportStatus.connectionEpoch,
      phase: _connectionPhase(transportStatus.phase),
    );
    if (_connectionStatusSubject.value != status) {
      _connectionStatusSubject.add(status);
    }

    if (transportStatus.phase != RealtimeTransportPhase.authenticated ||
        transportStatus.accountId == null) {
      return;
    }
    if (_hasAuthenticatedCurrentAccount) {
      _catchUpController.add(
        RealtimeCatchUp(
          accountId: transportStatus.accountId!,
          connectionEpoch: transportStatus.connectionEpoch,
          reason: transportStatus.cause == RealtimeReconnectCause.pongTimeout
              ? RealtimeCatchUpReason.pongTimeout
              : RealtimeCatchUpReason.webSocketReconnected,
        ),
      );
    }
    _hasAuthenticatedCurrentAccount = true;
  }

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {
    final accountId = _activeAccountId;
    if (accountId == null) return;
    _catchUpController.add(
      RealtimeCatchUp(
        accountId: accountId,
        connectionEpoch: _latestConnectionEpoch,
        reason: reason,
      ),
    );
  }

  @override
  void replaceWatch(RealtimeWatchGrant grant) {
    _send(
      jsonEncode({
        'type': 'subscription',
        'path': 'entity_changes',
        'payload': {
          'intent': 'replace_watch',
          'scope': grant.scope.name,
          'grant': grant.token,
        },
      }),
    );
  }

  @override
  void removeWatch(RealtimeWatchScope scope) {
    _send(
      jsonEncode({
        'type': 'subscription',
        'path': 'entity_changes',
        'payload': {'intent': 'remove_watch', 'scope': scope.name},
      }),
    );
  }

  static Iterable<RealtimeEntityChange> _deduplicateEntityChanges(
    List<RealtimeEntityChange> batch,
  ) {
    final latestByProjectionKey =
        <(RealtimeEntityKind, String), RealtimeEntityChange>{};
    for (final change in batch) {
      latestByProjectionKey[(change.kind, change.aggregateId)] = change;
    }
    return latestByProjectionKey.values;
  }

  static Iterable<RealtimeCatchUp> _deduplicateCatchUps(
    List<RealtimeCatchUp> batch,
  ) {
    final latestByGeneration = <(String, int), RealtimeCatchUp>{};
    for (final catchUp in batch) {
      latestByGeneration[(catchUp.accountId, catchUp.connectionEpoch)] =
          catchUp;
    }
    return latestByGeneration.values;
  }

  static RealtimeConnectionPhase _connectionPhase(
    RealtimeTransportPhase phase,
  ) => switch (phase) {
    RealtimeTransportPhase.unbound => RealtimeConnectionPhase.unbound,
    RealtimeTransportPhase.connecting => RealtimeConnectionPhase.connecting,
    RealtimeTransportPhase.authenticating =>
      RealtimeConnectionPhase.authenticating,
    RealtimeTransportPhase.authenticated =>
      RealtimeConnectionPhase.authenticated,
    RealtimeTransportPhase.disconnected => RealtimeConnectionPhase.disconnected,
  };

  static RealtimeEntityKind? _entityKindFromWire(Object? raw) => switch (raw) {
    'beacon' => RealtimeEntityKind.beacon,
    'forward' => RealtimeEntityKind.forward,
    'help_offer' => RealtimeEntityKind.helpOffer,
    'inbox_item' => RealtimeEntityKind.inboxItem,
    'room_message' => RealtimeEntityKind.roomMessage,
    'room_reaction' => RealtimeEntityKind.roomReaction,
    'room_poll' => RealtimeEntityKind.roomPoll,
    'participant' => RealtimeEntityKind.participant,
    'fact_card' => RealtimeEntityKind.factCard,
    'blocker' => RealtimeEntityKind.blocker,
    'activity_event' => RealtimeEntityKind.activityEvent,
    'coordination_item' => RealtimeEntityKind.coordinationItem,
    'capability' || 'person_capability_event' => RealtimeEntityKind.capability,
    'contact' => RealtimeEntityKind.contact,
    'room_seen' => RealtimeEntityKind.roomSeen,
    'relationship' => RealtimeEntityKind.relationship,
    'profile' => RealtimeEntityKind.profile,
    'notification' => RealtimeEntityKind.notification,
    _ => null,
  };

  static RealtimeOperation? _operationFromWire(Object? raw) => switch (raw) {
    'insert' => RealtimeOperation.insert,
    'update' => RealtimeOperation.update,
    'delete' => RealtimeOperation.delete,
    _ => null,
  };

  static BeaconRoomInvalidation? _toBeaconRoomInvalidation(
    RealtimeEntityChange change,
  ) {
    final entityType = switch (change.kind) {
      RealtimeEntityKind.roomMessage => BeaconRoomEntityType.roomMessage,
      RealtimeEntityKind.participant => BeaconRoomEntityType.participant,
      RealtimeEntityKind.factCard => BeaconRoomEntityType.factCard,
      RealtimeEntityKind.blocker => BeaconRoomEntityType.blocker,
      RealtimeEntityKind.activityEvent => BeaconRoomEntityType.activityEvent,
      RealtimeEntityKind.coordinationItem =>
        BeaconRoomEntityType.coordinationItem,
      _ => null,
    };
    return entityType == null
        ? null
        : BeaconRoomInvalidation(
            beaconId: change.aggregateId,
            entityType: entityType,
          );
  }

  /// WebSocket `jsonDecode` may retain JS-backed values; round-trip so payload
  /// values are plain Dart objects before closed-enum mapping.
  static Map<String, dynamic>? _normalizeJsonObject(Object? value) {
    if (value == null) return null;
    try {
      final decoded = jsonDecode(jsonEncode(value));
      if (decoded is! Map) return null;
      return Map<String, dynamic>.from(decoded);
    } on Object {
      return null;
    }
  }

  @disposeMethod
  Future<void> dispose() async {
    await _messageSubscription.cancel();
    await _transportSubscription.cancel();
    await _entityChangeController.close();
    await _catchUpController.close();
    await _connectionStatusSubject.close();
  }
}
