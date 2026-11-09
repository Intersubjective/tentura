import 'package:logging/logging.dart';

import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/env.dart';

/// Room message spam control shared by the room and baton use cases.
extension RoomMessageRateLimit on BeaconRoomRepositoryPort {
  /// Rejects when [userId] has posted [Env.roomMessageMaxPerUser] or more room
  /// messages within [Env.roomMessageRateWindow] (across all beacons and
  /// threads). [logger], when given, records the refusal.
  Future<void> enforceMessageRateLimit({
    required String userId,
    required Env env,
    Logger? logger,
  }) async {
    final recent = await countRecentMessagesByAuthor(
      authorId: userId,
      window: env.roomMessageRateWindow,
    );
    if (recent >= env.roomMessageMaxPerUser) {
      logger?.info('room message rate-limited for user $userId');
      throw const RateLimitedException(
        description: 'Too many messages sent, please slow down',
      );
    }
  }
}
