import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/env.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/entity/realtime_watch_grant.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/realtime_watch_grant_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/domain/port/beacon_room_co_participant_lookup_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';

import 'websocket_user_session.dart';

export 'package:shelf_plus/shelf_plus.dart' show WebSocketSession;

base class WebsocketSessionHandlerBase {
  WebsocketSessionHandlerBase(
    this.env,
    this.logger,
    this.authCase,
    this.userPresenceCase,
    this.friendshipLookup,
    this.coParticipantLookup,
    this.realtimeWatchGrantCase,
  );

  final Env env;

  final Logger logger;

  final AuthCase authCase;

  final UserPresenceCase userPresenceCase;

  final VoteUserFriendshipLookupPort friendshipLookup;

  final BeaconRoomCoParticipantLookupPort coParticipantLookup;

  final RealtimeWatchGrantCase realtimeWatchGrantCase;

  final _sessions = <WebSocketSession, WebsocketUserSession>{};

  /// Reverse index: userId -> set of WebSocket sessions for that user.
  final _sessionsByUserId = <String, Set<WebSocketSession>>{};

  /// Per session: peer user ids this client wants presence updates for.
  final _presencePeerIdsBySession = <WebSocketSession, Set<String>>{};

  final _entityWatchesBySession =
      <WebSocketSession, Map<RealtimeWatchScope, _EntityWatchRegistration>>{};

  /// Isolate-local reverse watch index; it is never shared between workers.
  final _watchSessionsBySubject = <String, Set<WebSocketSession>>{};

  /// Returns all active sessions for a given userId (possibly empty).
  Set<WebSocketSession> getSessionsByUserId(String userId) =>
      Set.unmodifiable(_sessionsByUserId[userId] ?? const {});

  /// Isolate-local snapshot used for control broadcasts.
  List<WebSocketSession> get authenticatedSessions =>
      List.unmodifiable(_sessions.keys);

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
    _removeAllEntityWatches(session);
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

  Future<void> replaceEntityWatch(
    WebSocketSession session, {
    required RealtimeWatchScope scope,
    required String grantToken,
  }) async {
    if (!env.realtimeWatchEnabled) {
      throw UnsupportedError('Realtime watches are disabled');
    }
    final jwt = getJwtBySession(session);
    final claims = realtimeWatchGrantCase.verify(
      token: grantToken,
      accountId: jwt.sub,
      expectedScope: scope,
    );
    if (claims == null || !claims.expiresAt.isAfter(DateTime.timestamp())) {
      throw const UnauthorizedException(
        description: 'Invalid realtime watch grant',
      );
    }

    _removeEntityWatch(session, scope);
    final registration = _EntityWatchRegistration(claims);
    (_entityWatchesBySession[session] ??= {})[scope] = registration;
    for (final subjectId in claims.subjectIds) {
      (_watchSessionsBySubject[subjectId] ??= {}).add(session);
    }
    registration.expiryTimer = Timer(
      claims.expiresAt.difference(DateTime.timestamp()),
      () {
        final current = _entityWatchesBySession[session]?[scope];
        if (current?.claims.tokenId == claims.tokenId) {
          _removeEntityWatch(session, scope);
        }
      },
    );
    session.send(
      jsonEncode({
        'type': 'subscription',
        'path': 'entity_changes',
        'payload': {
          'intent': 'watch_registered',
          'scope': scope.name,
          'subject_count': claims.subjectIds.length,
          'expires_at': claims.expiresAt.toIso8601String(),
        },
      }),
    );
    logger.info(
      '[WebsocketSessionHandlerBase] Replaced ${scope.name} watch '
      '(subjects ${claims.subjectIds.length}, active sessions '
      '${_entityWatchesBySession.length})',
    );
  }

  void removeEntityWatch(
    WebSocketSession session,
    RealtimeWatchScope scope,
  ) => _removeEntityWatch(session, scope);

  /// Returns only each session's authorized intersection with [subjectIds].
  Map<WebSocketSession, Set<String>> watchIntersections(
    Iterable<String> subjectIds,
  ) {
    final intersections = <WebSocketSession, Set<String>>{};
    final now = DateTime.timestamp();
    for (final subjectId in subjectIds.toSet()) {
      final sessions = {...?_watchSessionsBySubject[subjectId]};
      for (final session in sessions) {
        final registrations = _entityWatchesBySession[session];
        if (registrations == null) continue;
        var authorized = false;
        for (final entry in registrations.entries.toList()) {
          if (!entry.value.claims.expiresAt.isAfter(now)) {
            _removeEntityWatch(session, entry.key);
          } else if (entry.value.claims.subjectIds.contains(subjectId)) {
            authorized = true;
          }
        }
        if (authorized) {
          (intersections[session] ??= {}).add(subjectId);
        }
      }
    }
    return intersections;
  }

  int get activeEntityWatchSessionCount => _entityWatchesBySession.length;

  int get activeEntityWatchSubjectCount => _watchSessionsBySubject.length;

  void _removeEntityWatch(
    WebSocketSession session,
    RealtimeWatchScope scope,
  ) {
    final registrations = _entityWatchesBySession[session];
    final removed = registrations?.remove(scope);
    if (removed == null) return;
    removed.expiryTimer?.cancel();
    for (final subjectId in removed.claims.subjectIds) {
      final sessions = _watchSessionsBySubject[subjectId];
      sessions?.remove(session);
      if (sessions?.isEmpty ?? false) {
        _watchSessionsBySubject.remove(subjectId);
      }
    }
    if (registrations!.isEmpty) {
      _entityWatchesBySession.remove(session);
    }
  }

  void _removeAllEntityWatches(WebSocketSession session) {
    final scopes = _entityWatchesBySession[session]?.keys.toList() ?? const [];
    for (final scope in scopes) {
      _removeEntityWatch(session, scope);
    }
  }

  void setPresenceWatchPeers(
    WebSocketSession session,
    Set<String> peerIds,
  ) {
    // Replace, don't union: each `watch_updates` subscription carries the full
    // intended peer list, so unioning would let the watch set grow unbounded
    // and keep fanning out presence for peers the client no longer watches.
    _presencePeerIdsBySession[session] = {...peerIds};
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
      session.send(
        jsonEncode({
          'type': 'pong',
          'min_client_version': env.minClientVersion,
        }),
      );
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
        final previousJwt = removeSession(session);
        // If this socket was authenticated as a different user, surface that
        // user's offline transition to their watchers (removeSession does not
        // broadcast). Skip when they still have other live sessions.
        if (previousJwt != null &&
            previousJwt.sub != jwt.sub &&
            !hasSessionsForUser(previousJwt.sub)) {
          await userPresenceCase.setStatus(
            userId: previousJwt.sub,
            status: UserPresenceStatus.offline,
          );
          await broadcastPresenceForUser(previousJwt.sub);
        }
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

final class _EntityWatchRegistration {
  _EntityWatchRegistration(this.claims);

  final RealtimeWatchGrantClaims claims;
  Timer? expiryTimer;
}
