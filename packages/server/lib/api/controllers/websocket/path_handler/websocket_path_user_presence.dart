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
      'set_status' => userPresenceCase.setStatus(
        userId: jwt.sub,
        status: UserPresenceStatus.values.firstWhere(
          (e) => e.name == payload['status'] as String?,
        ),
      ),
      _ => throw UnsupportedError('$intent is not supported!'),
    };
  }
}
