import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/domain/entity/jwt_entity.dart';

import '../session/websocket_session_handler_base.dart';

base mixin WebsocketPathUserPresence on WebsocketSessionHandlerBase {
  Future<void> onUserPresence(
    JwtEntity jwt,
    Map<String, dynamic> payload,
  ) async {
    final intent = payload['intent'];
    return switch (intent) {
      'set_status' => _onSetStatus(jwt, payload),
      _ => throw UnsupportedError('$intent is not supported!'),
    };
  }

  Future<void> _onSetStatus(JwtEntity jwt, Map<String, dynamic> payload) async {
    await userPresenceCase.setStatus(
      userId: jwt.sub,
      status: UserPresenceStatus.values.firstWhere(
        (e) => e.name == payload['status'] as String?,
      ),
    );
    await broadcastPresenceForUser(jwt.sub);
  }

  /// One-time snapshot + watch list for peer presence; live updates via NOTIFY
  /// fan-out from [broadcastPresenceForUser].
  Future<void> onUserPresenceSubscription(
    WebSocketSession session,
    Map<String, dynamic> payload,
  ) async {
    switch (payload['intent']) {
      case 'watch_updates':
        final params = payload['params'];
        if (params is! Map<String, dynamic>) {
          throw const FormatException('Invalid params');
        }
        final raw = params['peer_ids'];
        final peerIds =
            raw is List ? raw.map((e) => e as String).toList() : <String>[];
        await sendPresenceSnapshotForPeers(session, peerIds);

      default:
        throw UnsupportedError(
          '${payload['intent']} is not supported!',
        );
    }
  }
}
