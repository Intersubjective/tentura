import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';

import 'websocket_user_session.dart';

export 'package:shelf_plus/shelf_plus.dart' show WebSocketSession;

base class WebsocketSessionHandlerBase {
  WebsocketSessionHandlerBase(
    this.env,
    this.logger,
    this.authCase,
    this.userPresenceCase,
  );

  final Env env;

  final Logger logger;

  final AuthCase authCase;

  final UserPresenceCase userPresenceCase;

  final _sessions = <WebSocketSession, WebsocketUserSession>{};

  /// Reverse index: userId -> set of WebSocket sessions for that user.
  final _sessionsByUserId = <String, Set<WebSocketSession>>{};

  /// Per session: peer user ids this client wants presence updates for.
  final _presencePeerIdsBySession = <WebSocketSession, Set<String>>{};

  /// Returns all active sessions for a given userId (possibly empty).
  Set<WebSocketSession> getSessionsByUserId(String userId) =>
      _sessionsByUserId[userId] ?? const {};

  /// Returns true if any session exists for the given userId.
  bool hasSessionsForUser(String userId) =>
      _sessionsByUserId[userId]?.isNotEmpty ?? false;

  JwtEntity? touchSession(WebSocketSession session) {
    final userSession = _sessions[session];
    userSession?.touch();
    return userSession?.jwt;
  }

  JwtEntity? removeSession(WebSocketSession session) {
    final removedSession = _sessions.remove(session);
    _presencePeerIdsBySession.remove(session);
    if (removedSession != null) {
      removedSession.cancel();
      final userId = removedSession.jwt.sub;
      final userSessions = _sessionsByUserId[userId];
      if (userSessions != null) {
        userSessions.remove(session);
        if (userSessions.isEmpty) {
          _sessionsByUserId.remove(userId);
        }
      }
    }
    return removedSession?.jwt;
  }

  void setPresenceWatchPeers(
    WebSocketSession session,
    Set<String> peerIds,
  ) {
    _presencePeerIdsBySession[session] = {
      ...?_presencePeerIdsBySession[session],
      ...peerIds,
    };
  }

  Iterable<WebSocketSession> _sessionsWatchingUser(String userId) sync* {
    for (final e in _presencePeerIdsBySession.entries) {
      if (e.value.contains(userId)) {
        yield e.key;
      }
    }
  }

  Map<String, dynamic> _presenceEventJson(UserPresenceEntity e) => {
    'user_id': e.userId,
    'status': e.status.name,
    'last_seen_at': e.lastSeenAt.toIso8601String(),
  };

  UserPresenceEntity _defaultPresence(String userId) => UserPresenceEntity(
    userId: userId,
    status: UserPresenceStatus.unknown,
    lastSeenAt: DateTime.fromMillisecondsSinceEpoch(0),
    lastNotifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
    offlineAfterDelay: env.chatStatusOfflineAfterDelay,
  );

  /// Sends current presence for [peerIds] to [session] and registers the watch list.
  Future<void> sendPresenceSnapshotForPeers(
    WebSocketSession session,
    List<String> peerIds,
  ) async {
    getJwtBySession(session);
    setPresenceWatchPeers(session, peerIds.toSet());
    final events = <Map<String, dynamic>>[];
    for (final id in peerIds) {
      final entity = await userPresenceCase.get(id) ?? _defaultPresence(id);
      events.add(_presenceEventJson(entity));
    }
    if (events.isEmpty) {
      return;
    }
    session.send(
      jsonEncode({
        'type': 'subscription',
        'path': 'user_presence',
        'payload': {
          'intent': 'watch_updates',
          'events': events,
        },
      }),
    );
  }

  /// Fan-out presence for [userId] to all sessions that subscribed to that peer.
  Future<void> broadcastPresenceForUser(String userId) async {
    final entity =
        await userPresenceCase.get(userId) ?? _defaultPresence(userId);
    final json = jsonEncode({
      'type': 'subscription',
      'path': 'user_presence',
      'payload': {
        'intent': 'watch_updates',
        'events': [_presenceEventJson(entity)],
      },
    });
    for (final s in _sessionsWatchingUser(userId)) {
      s.send(json);
    }
  }

  JwtEntity getJwtBySession(WebSocketSession session) =>
      _sessions[session]?.jwt ?? (throw const UnauthorizedException());

  void addWorker(
    WebSocketSession session, {
    required Timer worker,
  }) => _sessions[session]?.addWorker(worker);

  Future<void> onPing(
    WebSocketSession session,
    Map<String, dynamic> message,
  ) async {
    final jwt = touchSession(session);
    if (jwt != null) {
      if (env.isPongEnabled) {
        session.send(
          jsonEncode({
            'type': 'pong',
            'min_client_version': env.minClientVersion,
          }),
        );
      }
      await userPresenceCase.touch(userId: jwt.sub);
    }
  }

  Future<void> onAuth(
    WebSocketSession session,
    Map<String, dynamic> message,
  ) async {
    switch (message['intent']) {
      case AuthRequestIntent.cnameSignIn:
        final jwt = authCase.parseAndVerifyJwt(
          token: message['token']! as String,
        );
        removeSession(session);
        _sessions[session] = WebsocketUserSession(jwt);
        (_sessionsByUserId[jwt.sub] ??= {}).add(session);
        session.send(_authLogInResponse);
        await userPresenceCase.setStatus(
          userId: jwt.sub,
          status: UserPresenceStatus.online,
        );
        await broadcastPresenceForUser(jwt.sub);
        logger.info(
          '[WebsocketSessionHandlerBase] Start session: [${jwt.sub}]',
        );

      case AuthRequestIntent.cnameSignOut:
        final jwt = removeSession(session);
        if (jwt != null) {
          session.send(_authLogOutResponse);
          await userPresenceCase.setStatus(
            userId: jwt.sub,
            status: UserPresenceStatus.offline,
          );
          await broadcastPresenceForUser(jwt.sub);
          logger.info(
            '[WebsocketSessionHandlerBase] Stop session: [${jwt.sub}]',
          );
        }

      default:
    }
  }

  static const _authLogInResponse =
      '{"type":"auth", '
      '"result":"success", '
      '"intent":"${AuthRequestIntent.cnameSignIn}"}';

  static const _authLogOutResponse =
      '{"type":"auth", '
      '"result":"success", '
      '"intent":"${AuthRequestIntent.cnameSignOut}"}';
}
