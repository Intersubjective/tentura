import 'package:tentura_server/consts/beacon_room_consts.dart';

/// Who may use a Request's room, shared by the room and baton use cases.
abstract final class RoomAccessPolicy {
  RoomAccessPolicy._();

  /// Who may use a Request's room, in this order: its author; nobody with a
  /// block either way with a Post's author; a steward; an admitted
  /// participant. Each fact is read only when the ones before do not decide.
  static Future<bool> canUseRoom({
    required Future<bool> Function() isAuthor,
    required Future<bool> Function() isBlockedFromPost,
    required Future<bool> Function() isSteward,
    required Future<int?> Function() roomAccess,
  }) async {
    if (await isAuthor()) return true;
    if (await isBlockedFromPost()) return false;
    if (await isSteward()) return true;
    return await roomAccess() == RoomAccessBits.admitted;
  }
}
