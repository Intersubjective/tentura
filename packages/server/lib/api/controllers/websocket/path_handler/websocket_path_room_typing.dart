import 'dart:async';
import 'dart:convert';

import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';

import '../session/websocket_session_handler_base.dart';

/// Ephemeral "is typing" intents for a Request room. Nothing is stored or
/// replayed: a member's `start` is relayed to the room's other connected
/// members, at most once per [relayInterval] per sender and room, and a typist
/// who stops refreshing is announced as stopped after [expiry].
base mixin WebsocketPathRoomTyping on WebsocketSessionHandlerBase {
  static const relayInterval = Duration(seconds: 3);

  static const expiry = Duration(seconds: 6);

  /// Per (typist, room): who is announced as typing from this worker.
  final _typing = <String, _TypingState>{};

  Future<void> onRoomTyping(
    JwtEntity jwt,
    Map<String, dynamic> payload,
  ) async {
    final beaconId = payload['beacon_id'];
    if (beaconId is! String || beaconId.isEmpty) {
      throw const FormatException('Invalid beacon_id');
    }
    final key = _key(jwt.sub, beaconId);
    switch (payload['intent']) {
      case 'start':
        var state = _typing[key];
        if (state == null) {
          await _ensureMember(jwt.sub, beaconId);
          // A concurrent intent may have been admitted while we waited.
          state = _typing[key];
        }
        if (state == null) {
          _typing[key] = _TypingState(
            Timer(expiry, () => _expire(jwt.sub, beaconId)),
            DateTime.timestamp(),
          );
          await announceRoomTyping(beaconId, jwt.sub, typing: true);
          return;
        }
        state.expiryTimer.cancel();
        state.expiryTimer = Timer(expiry, () => _expire(jwt.sub, beaconId));
        if (DateTime.timestamp().difference(state.lastRelayedAt) >=
            relayInterval) {
          state.lastRelayedAt = DateTime.timestamp();
          await announceRoomTyping(beaconId, jwt.sub, typing: true);
        }

      case 'stop':
        if (_typing.containsKey(key)) {
          await _stop(jwt.sub, beaconId);
        } else {
          await _ensureMember(jwt.sub, beaconId);
        }

      default:
        throw FormatException('Unknown typing intent: ${payload['intent']}');
    }
  }

  /// Announces [userId] as stopped everywhere they are typing from this
  /// worker once their last socket here is gone.
  @override
  JwtEntity? removeSession(WebSocketSession session) {
    final jwt = super.removeSession(session);
    if (jwt != null && !hasSessionsForUser(jwt.sub)) {
      for (final key in _typing.keys.toList()) {
        if (key.startsWith('${jwt.sub}|')) {
          unawaited(_stopQuietly(jwt.sub, key.substring(jwt.sub.length + 1)));
        }
      }
    }
    return jwt;
  }

  /// Cancels the pending expiry timers (worker shutdown).
  void disposeRoomTyping() {
    for (final state in _typing.values) {
      state.expiryTimer.cancel();
    }
    _typing.clear();
  }

  /// Tells the room's other members that [userId] started or stopped typing.
  /// This base handler only knows its own sockets; `WebsocketRouterBase`
  /// carries it to every web worker over Postgres NOTIFY, and each worker
  /// then runs [fanOutRoomTyping].
  Future<void> announceRoomTyping(
    String beaconId,
    String userId, {
    required bool typing,
  }) => fanOutRoomTyping(beaconId, userId, typing: typing);

  /// Sends the typing frame to the sockets on this worker of the room's
  /// members, the typist's own sockets excluded.
  Future<void> fanOutRoomTyping(
    String beaconId,
    String userId, {
    required bool typing,
  }) async {
    if (authenticatedSessions.isEmpty) return;
    final members = await coParticipantLookup.roomMemberUserIds(
      beaconId: beaconId,
    );
    final frame = jsonEncode({
      'type': 'subscription',
      'path': 'room_typing',
      'payload': {
        'beacon_id': beaconId,
        'user_id': userId,
        'typing': typing,
      },
    });
    for (final member in members) {
      if (member == userId) continue;
      for (final session in getSessionsByUserId(member)) {
        session.send(frame);
      }
    }
  }

  Future<void> _ensureMember(String userId, String beaconId) async {
    final members = await coParticipantLookup.roomMemberUserIds(
      beaconId: beaconId,
    );
    if (!members.contains(userId)) {
      throw const UnauthorizedException(
        description: 'Only room members can send typing intents',
      );
    }
  }

  void _expire(String userId, String beaconId) =>
      unawaited(_stopQuietly(userId, beaconId));

  Future<void> _stopQuietly(String userId, String beaconId) async {
    try {
      await _stop(userId, beaconId);
    } on Object catch (e) {
      logger.warning('[WebsocketPathRoomTyping] stop relay failed: $e');
    }
  }

  Future<void> _stop(String userId, String beaconId) async {
    final state = _typing.remove(_key(userId, beaconId));
    if (state == null) return;
    state.expiryTimer.cancel();
    await announceRoomTyping(beaconId, userId, typing: false);
  }

  static String _key(String userId, String beaconId) => '$userId|$beaconId';
}

final class _TypingState {
  _TypingState(this.expiryTimer, this.lastRelayedAt);

  Timer expiryTimer;

  DateTime lastRelayedAt;
}
