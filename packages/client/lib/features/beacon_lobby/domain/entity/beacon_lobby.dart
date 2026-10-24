import 'package:freezed_annotation/freezed_annotation.dart';

part 'beacon_lobby.freezed.dart';

/// Why the viewer may only read Questions, or may not open it at all — told
/// by the server, only about the viewer themselves (#657).
enum BeaconLobbyLimitReason {
  /// The Request is closed: read-only for everyone.
  closed,

  /// The viewer answered "Can't help".
  cantHelp,

  /// The viewer withdrew their help offer.
  withdrew,

  /// The author declined the viewer's help offer.
  declined,

  /// The author removed the viewer from Questions.
  removed;

  /// The server's `readOnlyReason`; null for a missing or unknown value.
  static BeaconLobbyLimitReason? fromWire(String? wire) => switch (wire) {
    'closed' => closed,
    'cant_help' => cantHelp,
    'withdrew' => withdrew,
    'declined' => declined,
    'removed' => removed,
    _ => null,
  };
}

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

    /// The Request author: their answers are marked as the author's.
    @Default('') String authorId,

    /// The viewer is inside already (a live help offer, admitted, or a
    /// steward), not the author (#657).
    @Default(false) bool isHelper,

    /// False from Final check on: nobody can offer help any more (#657).
    @Default(true) bool takesOffers,

    /// Why [canPost] is false, when the server can say.
    BeaconLobbyLimitReason? readOnlyReason,

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

    /// Why the viewer reads only, or cannot open Questions, when the server
    /// can say.
    BeaconLobbyLimitReason? limitReason,

    /// The viewer is inside already (a live help offer, admitted, or a
    /// steward), not the author (#657).
    @Default(false) bool isHelper,

    /// False from Final check on: nobody can offer help any more (#657).
    @Default(true) bool takesOffers,
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
