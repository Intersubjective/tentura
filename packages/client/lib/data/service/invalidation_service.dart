import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';

import 'remote_api_service.dart';

/// Receives entity-change invalidation signals from the V2 WebSocket and
/// exposes per-entity-type streams that repositories can listen to.
///
/// Incoming IDs are buffered for [_debounceWindow] and deduplicated so that
/// batch operations (e.g. multi-recipient forwards) produce a single
/// invalidation event per entity ID.
///
/// See DEV_GUIDELINES.md § "Entity invalidation (real-time)" for the full
/// data flow and the checklist for adding new entity types.
@singleton
class InvalidationService implements RealtimeSyncPort {
  InvalidationService(RemoteApiService remoteApiService) {
    _subscription = _subscribe(remoteApiService.webSocketMessages);
  }

  /// Unit tests without [RemoteApiService] / WebSocket wiring.
  @visibleForTesting
  InvalidationService.forTesting(Stream<Map<String, dynamic>> messages) {
    _subscription = _subscribe(messages);
  }

  StreamSubscription<Map<String, dynamic>> _subscribe(
    Stream<Map<String, dynamic>> messages,
  ) => messages
      .where(
        (e) => e['type'] == 'subscription' && e['path'] == 'entity_changes',
      )
      .listen(_onInvalidation);

  static const _debounceWindow = Duration(milliseconds: 500);

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final _entityChangeController =
      StreamController<RealtimeEntityChange>.broadcast();

  @override
  late final Stream<RealtimeEntityChange> entityChanges =
      _entityChangeController.stream
          .bufferTime(_debounceWindow)
          .where((batch) => batch.isNotEmpty)
          .expand(_deduplicateEntityChanges)
          .asBroadcastStream();

  /// Beacon ID that was changed by another user or session (debounced).
  late final Stream<String> beaconInvalidations = entityChanges
      .where((change) => change.kind == RealtimeEntityKind.beacon)
      .map((change) => change.aggregateId)
      .asBroadcastStream();

  /// Beacon ID whose help offers changed (debounced).
  late final Stream<String> helpOfferInvalidations = entityChanges
      .where((change) => change.kind == RealtimeEntityKind.helpOffer)
      .map((change) => change.aggregateId)
      .asBroadcastStream();

  /// Beacon ID whose forwards changed (debounced).
  late final Stream<String> forwardInvalidations = entityChanges
      .where((change) => change.kind == RealtimeEntityKind.forward)
      .map((change) => change.aggregateId)
      .asBroadcastStream();

  /// Beacon room slice invalidation (`room_message`, `participant`, etc.);
  /// payload `id` is the beacon id.
  late final Stream<BeaconRoomInvalidation> beaconRoomInvalidations =
      entityChanges
          .map(_toBeaconRoomInvalidation)
          .whereType<BeaconRoomInvalidation>()
          .asBroadcastStream();

  /// Subject user ID whose capability cues changed (`person_capability_event` NOTIFY branch).
  late final Stream<String> capabilityInvalidations = entityChanges
      .where((change) => change.kind == RealtimeEntityKind.capability)
      .map((change) => change.aggregateId)
      .asBroadcastStream();

  void _onInvalidation(Map<String, dynamic> msg) {
    final payload = _normalizeJsonObject(msg['payload']);
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

  /// WebSocket `jsonDecode` may retain JS-backed values; round-trip so
  /// `payload['entity']` / `id` are plain Dart strings for the switch above.
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
    await _subscription.cancel();
    await _entityChangeController.close();
  }
}
