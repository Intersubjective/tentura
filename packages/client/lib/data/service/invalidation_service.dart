import 'dart:async';
import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

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
    _subscription = remoteApiService.webSocketMessages
        .where(
          (e) =>
              e['type'] == 'subscription' && e['path'] == 'entity_changes',
        )
        .listen(_onInvalidation);
  }

  static const _debounceWindow = Duration(milliseconds: 500);

  late final StreamSubscription<Map<String, dynamic>> _subscription;

  final _beaconChanges = StreamController<String>.broadcast();
  final _commitmentChanges = StreamController<String>.broadcast();
  final _forwardChanges = StreamController<String>.broadcast();
  final _beaconRoomChanges = StreamController<String>.broadcast();

  /// Beacon ID that was changed by another user or session (debounced).
  late final Stream<String> beaconInvalidations = _beaconChanges.stream
      .bufferTime(_debounceWindow)
      .where((batch) => batch.isNotEmpty)
      .expand((batch) => batch.toSet())
      .asBroadcastStream();

  /// Beacon ID whose commitments changed (debounced).
  late final Stream<String> commitmentInvalidations =
      _commitmentChanges.stream
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

  /// Beacon ID whose room chat or participant rows changed (`room_message` /
  /// `participant` NOTIFY branches; payload `id` is the beacon).
  late final Stream<String> beaconRoomInvalidations =
      _beaconRoomChanges.stream
          .bufferTime(_debounceWindow)
          .where((batch) => batch.isNotEmpty)
          .expand((batch) => batch.toSet())
          .asBroadcastStream();

  void _onInvalidation(Map<String, dynamic> msg) {
    final payload = msg['payload'];
    if (payload is! Map<String, dynamic>) return;
    final id = payload['id'] as String?;
    if (id == null) return;

    switch (payload['entity']) {
      case 'beacon':
        _beaconChanges.add(id);
      case 'commitment':
        _commitmentChanges.add(id);
      case 'forward':
        _forwardChanges.add(id);
      case 'room_message':
      case 'participant':
      case 'fact_card':
      case 'blocker':
      case 'activity_event':
        _beaconRoomChanges.add(id);
    }
  }

  @disposeMethod
  Future<void> dispose() async {
    await _subscription.cancel();
    await _beaconChanges.close();
    await _commitmentChanges.close();
    await _forwardChanges.close();
    await _beaconRoomChanges.close();
  }
}
