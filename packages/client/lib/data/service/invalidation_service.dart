import 'dart:async';
import 'dart:convert';

import 'package:injectable/injectable.dart';
import 'package:meta/meta.dart';
import 'package:rxdart/rxdart.dart';

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
class InvalidationService {
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
  ) =>
      messages
          .where(
            (e) => e['type'] == 'subscription' && e['path'] == 'entity_changes',
          )
          .listen(_onInvalidation);

  static const _debounceWindow = Duration(milliseconds: 500);

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final _beaconChanges = StreamController<String>.broadcast();
  final _helpOfferChanges = StreamController<String>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _beaconRoomChanges =
      StreamController<BeaconRoomInvalidation>.broadcast();
  final _capabilityChanges = StreamController<String>.broadcast();

  /// Beacon ID that was changed by another user or session (debounced).
  late final Stream<String> beaconInvalidations = _beaconChanges.stream
      .bufferTime(_debounceWindow)
      .where((batch) => batch.isNotEmpty)
      .expand((batch) => batch.toSet())
      .asBroadcastStream();

  /// Beacon ID whose help offers changed (debounced).
  late final Stream<String> helpOfferInvalidations = _helpOfferChanges.stream
      .bufferTime(_debounceWindow)
      .where((batch) => batch.isNotEmpty)
      .expand((batch) => batch.toSet())
      .asBroadcastStream();

  /// Beacon ID whose forwards changed (debounced).
  late final Stream<String> forwardInvalidations = _forwardChanges.stream
      .bufferTime(_debounceWindow)
      .where((batch) => batch.isNotEmpty)
      .expand((batch) => batch.toSet())
      .asBroadcastStream();

  /// Beacon room slice invalidation (`room_message`, `participant`, etc.);
  /// payload `id` is the beacon id.
  late final Stream<BeaconRoomInvalidation> beaconRoomInvalidations =
      _beaconRoomChanges.stream
          .bufferTime(_debounceWindow)
          .where((batch) => batch.isNotEmpty)
          .expand((batch) => batch.toSet())
          .asBroadcastStream();

  /// Subject user ID whose capability cues changed (`person_capability_event` NOTIFY branch).
  late final Stream<String> capabilityInvalidations = _capabilityChanges.stream
      .bufferTime(_debounceWindow)
      .where((batch) => batch.isNotEmpty)
      .expand((batch) => batch.toSet())
      .asBroadcastStream();

  void _onInvalidation(Map<String, dynamic> msg) {
    final payload = _normalizeJsonObject(msg['payload']);
    if (payload == null) return;
    final id = payload['id'] as String?;
    if (id == null) return;

    switch (payload['entity']) {
      case 'beacon':
        _beaconChanges.add(id);
      case 'help_offer':
        _helpOfferChanges.add(id);
      case 'forward':
        _forwardChanges.add(id);
      case 'room_message':
        _beaconRoomChanges.add(
          BeaconRoomInvalidation(
            beaconId: id,
            entityType: BeaconRoomEntityType.roomMessage,
          ),
        );
      case 'participant':
        _beaconRoomChanges.add(
          BeaconRoomInvalidation(
            beaconId: id,
            entityType: BeaconRoomEntityType.participant,
          ),
        );
      case 'fact_card':
        _beaconRoomChanges.add(
          BeaconRoomInvalidation(
            beaconId: id,
            entityType: BeaconRoomEntityType.factCard,
          ),
        );
      case 'blocker':
        _beaconRoomChanges.add(
          BeaconRoomInvalidation(
            beaconId: id,
            entityType: BeaconRoomEntityType.blocker,
          ),
        );
      case 'activity_event':
        _beaconRoomChanges.add(
          BeaconRoomInvalidation(
            beaconId: id,
            entityType: BeaconRoomEntityType.activityEvent,
          ),
        );
      case 'coordination_item':
        _beaconRoomChanges.add(
          BeaconRoomInvalidation(
            beaconId: id,
            entityType: BeaconRoomEntityType.coordinationItem,
          ),
        );
      case 'person_capability_event':
        _capabilityChanges.add(id);
    }
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
    await _beaconChanges.close();
    await _helpOfferChanges.close();
    await _forwardChanges.close();
    await _beaconRoomChanges.close();
    await _capabilityChanges.close();
  }
}
