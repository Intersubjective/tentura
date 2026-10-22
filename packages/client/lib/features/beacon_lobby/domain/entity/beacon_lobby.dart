import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_lobby.freezed.dart';

/// Request **Questions** (internally the lobby, U088), as the viewer sees it.
/// Who may read or post is decided only by the server policy.
@freezed
abstract class BeaconLobbyInfo with _$BeaconLobbyInfo {
  const factory BeaconLobbyInfo({
    required String beaconId,

    /// Thread scope id of Questions (server `coordination_item` kind 7).
    required String lobbyId,
    required bool isAuthor,

    /// False for read-only standing ("Can't help", withdrew) or once the
    /// Request is closed: the thread stays readable.
    required bool canPost,

    /// Only filled for the author: the people they removed, with names.
    @Default(<BeaconLobbyBannedPerson>[]) List<BeaconLobbyBannedPerson> banned,
  }) = _BeaconLobbyInfo;
}

@freezed
abstract class BeaconLobbyBannedPerson with _$BeaconLobbyBannedPerson {
  const factory BeaconLobbyBannedPerson({
    required String userId,
    required String name,
  }) = _BeaconLobbyBannedPerson;
}

/// The viewer's own standing, for the Request's entry row.
@freezed
abstract class BeaconLobbyAccess with _$BeaconLobbyAccess {
  const factory BeaconLobbyAccess({
    required bool canRead,
    required bool canPost,
    @Default(0) int messageCount,
  }) = _BeaconLobbyAccess;
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
