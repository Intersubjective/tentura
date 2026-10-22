import 'package:injectable/injectable.dart';
import 'package:rxdart/rxdart.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';

import '../entity/beacon_lobby.dart';
import '../port/beacon_lobby_port.dart';

/// Request Questions (internally the lobby, U088): read, post, and (author)
/// remove / let back in.
@singleton
final class BeaconLobbyCase {
  const BeaconLobbyCase(this._port, this._realtime);

  final BeaconLobbyPort _port;
  final RealtimeSyncCase _realtime;

  Future<BeaconLobbyAccess> access(String beaconId) => _port.access(beaconId);

  Future<BeaconLobbyInfo> open(String beaconId) => _port.open(beaconId);

  Future<List<BeaconLobbyMessage>> messages({
    required String beaconId,
    required String lobbyId,
    DateTime? before,
  }) => _port.messages(beaconId: beaconId, lobbyId: lobbyId, before: before);

  Future<void> post({
    required String beaconId,
    required String lobbyId,
    required String body,
  }) => _port.post(beaconId: beaconId, lobbyId: lobbyId, body: body);

  Future<void> markSeen({required String beaconId, required String lobbyId}) =>
      _port.markSeen(beaconId: beaconId, lobbyId: lobbyId);

  Future<void> ban({required String beaconId, required String userId}) =>
      _port.ban(beaconId: beaconId, userId: userId);

  Future<void> unban({required String beaconId, required String userId}) =>
      _port.unban(beaconId: beaconId, userId: userId);

  /// A message of this Request may have changed (General or Questions: the
  /// hint carries no scope and no Questions text). Only the message page is
  /// refetched, never the access check.
  Stream<void> messageChanges(String beaconId) => _realtime
      .changesForAggregate(
        kinds: const {RealtimeEntityKind.roomMessage},
        aggregateId: beaconId,
      )
      .map((_) {});

  /// The viewer's standing may have changed (offer, forward, admission,
  /// Request status), or realtime caught up after a gap: re-open.
  Stream<void> accessChanges(String beaconId) => MergeStream<void>([
    _realtime
        .changesForAggregate(
          kinds: const {
            RealtimeEntityKind.helpOffer,
            RealtimeEntityKind.forward,
            RealtimeEntityKind.participant,
            RealtimeEntityKind.beacon,
            // "Can't help" moves the viewer's own inbox item (#655, #657).
            RealtimeEntityKind.inboxItem,
          },
          aggregateId: beaconId,
        )
        .map((_) {}),
    // A block either way hides that person's messages: start over.
    _realtime.blockMarkers.map((_) {}),
    _realtime.catchUps.map((_) {}),
  ]);
}
