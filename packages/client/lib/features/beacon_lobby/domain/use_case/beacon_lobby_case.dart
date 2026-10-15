import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import '../entity/beacon_lobby.dart';
import '../port/beacon_lobby_port.dart';

/// U088 — the Request lobby: read, post, and (author) remove / let back in.
@singleton
final class BeaconLobbyCase {
  const BeaconLobbyCase(this._port, this._realtime);

  final BeaconLobbyPort _port;
  final RealtimeSyncCase _realtime;

  Future<BeaconLobbyInfo> open(String beaconId) => _port.open(beaconId);

  Future<List<BeaconLobbyMessage>> messages({
    required String beaconId,
    required String lobbyId,
  }) => _port.messages(beaconId: beaconId, lobbyId: lobbyId);

  Future<void> post({
    required String beaconId,
    required String lobbyId,
    required String body,
  }) => _port.post(beaconId: beaconId, lobbyId: lobbyId, body: body);

  Future<void> ban({required String beaconId, required String userId}) =>
      _port.ban(beaconId: beaconId, userId: userId);

  Future<void> unban({required String beaconId, required String userId}) =>
      _port.unban(beaconId: beaconId, userId: userId);

  /// When the lobby may have changed: a room-message or help-offer hint for
  /// this Request (the author and admitted helpers get these), or a realtime
  /// catch-up. The hint carries no lobby text; the lobby is refetched.
  Stream<void> lobbyChanges(String beaconId) => MergeStream<void>([
    _realtime
        .changesForAggregate(
          kinds: const {
            RealtimeEntityKind.roomMessage,
            RealtimeEntityKind.helpOffer,
          },
          aggregateId: beaconId,
        )
        .map((_) {}),
    _realtime.catchUps.map((_) {}),
  ]);
}
