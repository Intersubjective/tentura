import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_lobby.freezed.dart';

/// U088 — the Request lobby, as the viewer sees it.
@freezed
abstract class BeaconLobbyInfo with _$BeaconLobbyInfo {
  const factory BeaconLobbyInfo({
    required String beaconId,

    /// Thread scope id of the lobby (server `coordination_item` kind 7).
    required String lobbyId,
    required bool isAuthor,

    /// False once the Request is closed: the lobby stays readable.
    required bool canPost,

    /// Only filled for the author.
    @Default(<String>[]) List<String> bannedUserIds,
  }) = _BeaconLobbyInfo;
}

@freezed
abstract class BeaconLobbyMessage with _$BeaconLobbyMessage {
  const factory BeaconLobbyMessage({
    required String id,
    required String authorId,
    required String authorName,
    required String body,
    DateTime? createdAt,
  }) = _BeaconLobbyMessage;
}
