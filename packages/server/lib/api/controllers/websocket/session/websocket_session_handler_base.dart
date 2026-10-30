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
import 'package:tentura_server/domain/port/beacon_room_co_participant_lookup_port.dart';
import 'package:tentura_server/domain/port/room_message_snapshot_lookup_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';

import 'websocket_user_session.dart';
import 'qa_realtime_socket_gate.dart';

export 'package:shelf_plus/shelf_plus.dart' show WebSocketSession;

base class WebsocketSessionHandlerBase {
  WebsocketSessionHandlerBase(
    this.env,
    this.logger,
    this.authCase,
    this.userPresenceCase,
    this.friendshipLookup,
    this.coParticipantLookup,
    this.roomMessageSnapshotLookup,
    this.qaRealtimeSocketGate, {
    this.presenceOfflineGrace = defaultPresenceOfflineGrace,
  });

  /// How long a user whose last socket on this worker closed stays "online"
  /// before this worker stores "offline". A reload or a new tab usually
  /// reconnects within it, often on another worker, so watchers never see a
  /// false "offline" in between (#533).
  static const defaultPresenceOfflineGrace = Duration(seconds: 3);

  final Env env;

  final Logger logger;

  final AuthCase authCase;

  final UserPresenceCase userPresenceCase;

  final VoteUserFriendshipLookupPort friendshipLookup;

  final BeaconRoomCoParticipantLookupPort coParticipantLookup;

  final RoomMessageSnapshotLookupPort roomMessageSnapshotLookup;

  final QaRealtimeSocketGate qaRealtimeSocketGate;

  final Duration presenceOfflineGrace;

  final _sessions = <WebSocketSession, WebsocketUserSession>{};

  /// Reverse index: userId -> set of WebSocket sessions for that user.
  final _sessionsByUserId = <String, Set<WebSocketSession>>{};

  /// Per session: peer user ids this client wants presence updates for.
  final _presencePeerIdsBySession = <WebSocketSession, Set<String>>{};

  /// Per user: the last queued presence write on this worker. Writes for one
  /// user run one after another, so an "online" and an "offline" from this
  /// isolate land in the order they were made (#533).
  final _presenceWriteTails = <String, Future<void>>{};

  /// Pending "store offline after the grace period" timers.
  final _offlineGraceTimers = <Timer>{};

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
    qaRealtimeSocketGate.unregisterSession(session);
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
    // Replace, don't union: each `watch_updates` subscription carries the full
    // intended peer list, so unioning would let the watch set grow unbounded
    // and keep fanning out presence for peers the client no longer watches.
    _presencePeerIdsBySession[session] = {...peerIds};
  }

  /// Users whose presence this worker's sockets care about: watched peers and
  /// users with a socket here.
  Set<String> get locallyRelevantPresenceUserIds => {
    for (final peerIds in _presencePeerIdsBySession.values) ...peerIds,
    ..._sessionsByUserId.keys,
  };

  /// Cancels the pending offline grace timers (worker shutdown).
  void cancelPendingPresenceWrites() {
    for (final timer in _offlineGraceTimers) {
      timer.cancel();
    }
    _offlineGraceTimers.clear();
  }

  /// Runs [write] after every earlier presence write for [userId] on this
  /// worker has finished.
  Future<T> _queuePresenceWrite<T>(
    String userId,
    Future<T> Function() write,
  ) {
    final previous = _presenceWriteTails[userId] ?? Future<void>.value();
    final result = previous.then((_) => write());
    final tail = result.then<void>((_) {}, onError: (Object _) {});
    _presenceWriteTails[userId] = tail;
    unawaited(
      tail.whenComplete(() {
        if (identical(_presenceWriteTails[userId], tail)) {
          // The removed value is this drained tail.
          unawaited(_presenceWriteTails.remove(userId));
        }
      }),
    );
    return result;
  }

  Future<void> _setPresenceStatus(String userId, UserPresenceStatus status) =>
      _queuePresenceWrite(
        userId,
        () => userPresenceCase.setStatus(userId: userId, status: status),
      );

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

  /// Tells every watcher of [userId] its current presence.
  ///
  /// This base handler only knows its own sockets; `WebsocketRouterBase`
  /// carries the change to every web worker over Postgres NOTIFY, and each
  /// worker then runs [fanOutPresenceLocally] (#533).
  Future<void> broadcastPresenceForUser(String userId) =>
      fanOutPresenceLocally(userId);

  /// Sends [userId]'s stored presence to the sockets on this worker that
  /// watch them.
  ///
  /// A user is offline only when their last socket on every worker is gone,
  /// and a worker sees only its own sockets: when a tab on another worker (or
  /// an old tab closing late) stored "offline" while this worker still holds
  /// a live socket of theirs, this worker puts "online" back and announces
  /// that instead of showing a live person as gone (#533).
  Future<void> fanOutPresenceLocally(String userId) async {
    final watchers = _sessionsWatchingUser(userId).toList();
    final hasLocalSession = hasSessionsForUser(userId);
    if (watchers.isEmpty && !hasLocalSession) return;
    final entity =
        await userPresenceCase.get(userId) ?? _defaultPresence(userId);
    if (entity.status == UserPresenceStatus.offline &&
        hasLocalSession &&
        await _repairOnline(userId)) {
      await broadcastPresenceForUser(userId);
      return;
    }
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

  /// Stores "online" for [userId] while this worker still holds a socket of
  /// theirs. If that socket closed while the write was in flight, "offline"
  /// is written right after it, so the user cannot be left stuck online.
  /// Returns false when there was no socket left to repair for.
  Future<bool> _repairOnline(String userId) => _queuePresenceWrite(
    userId,
    () async {
      if (!hasSessionsForUser(userId)) return false;
      await userPresenceCase.setStatus(
        userId: userId,
        status: UserPresenceStatus.online,
      );
      if (!hasSessionsForUser(userId)) {
        await userPresenceCase.setStatus(
          userId: userId,
          status: UserPresenceStatus.offline,
        );
      }
      return true;
    },
  );

  /// Another worker's last socket of [userId] closed: when this worker still
  /// holds one, it stores "online" with a fresh timestamp, which tells the
  /// closing worker not to store "offline" after its grace period.
  Future<void> claimPresenceIfLocal(String userId) async {
    final changed = await _queuePresenceWrite(userId, () async {
      if (!hasSessionsForUser(userId)) return false;
      final before = await userPresenceCase.get(userId);
      await userPresenceCase.setStatus(
        userId: userId,
        status: UserPresenceStatus.online,
      );
      return before?.status != UserPresenceStatus.online;
    });
    if (changed) await broadcastPresenceForUser(userId);
  }

  /// Tells the other workers that [userId]'s last socket here closed. This
  /// base handler knows no other worker; `WebsocketRouterBase` sends it over
  /// Postgres NOTIFY, and a worker that still holds a socket of theirs
  /// answers through [claimPresenceIfLocal].
  Future<void> announcePresenceLeaving(String userId) async {}

  /// A socket is gone (closed or failed): forget it and, when it was the
  /// user's last socket on this worker, store and announce "offline" after
  /// [presenceOfflineGrace] unless they came back meanwhile, here or on
  /// another worker.
  Future<void> onSessionGone(WebSocketSession session) async {
    final jwt = removeSession(session);
    if (jwt == null || hasSessionsForUser(jwt.sub)) return;
    final userId = jwt.sub;
    final closedAt = DateTime.timestamp();
    late final Timer timer;
    timer = Timer(presenceOfflineGrace, () {
      _offlineGraceTimers.remove(timer);
      unawaited(_storeOfflineUnlessBack(userId, closedAt));
    });
    _offlineGraceTimers.add(timer);
    await announcePresenceLeaving(userId);
  }

  Future<void> _storeOfflineUnlessBack(String userId, DateTime closedAt) async {
    try {
      final stored = await _queuePresenceWrite(userId, () async {
        if (hasSessionsForUser(userId)) return false;
        final entity = await userPresenceCase.get(userId);
        // Already offline, or stored online by a socket that is newer than
        // ours: on another worker, a new tab or a reload is live.
        if (entity?.status == UserPresenceStatus.offline ||
            (entity?.status == UserPresenceStatus.online &&
                entity!.lastSeenAt.isAfter(closedAt))) {
          return false;
        }
        await userPresenceCase.setStatus(
          userId: userId,
          status: UserPresenceStatus.offline,
        );
        return true;
      });
      if (stored) await broadcastPresenceForUser(userId);
    } on Object catch (e) {
      logger.warning(
        '[WebsocketSessionHandlerBase] offline after grace failed: $e',
      );
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
        if (qaRealtimeSocketGate.isAuthenticationSuspended(jwt.sub)) {
          await session.sender.close(4003, 'QA realtime authentication paused');
          return;
        }
        final previousJwt = removeSession(session);
        // If this socket was authenticated as a different user, surface that
        // user's offline transition to their watchers (removeSession does not
        // broadcast). Skip when they still have other live sessions.
        if (previousJwt != null &&
            previousJwt.sub != jwt.sub &&
            !hasSessionsForUser(previousJwt.sub)) {
          await _setPresenceStatus(
            previousJwt.sub,
            UserPresenceStatus.offline,
          );
          await broadcastPresenceForUser(previousJwt.sub);
        }
        _sessions[session] = WebsocketUserSession(jwt);
        (_sessionsByUserId[jwt.sub] ??= {}).add(session);
        qaRealtimeSocketGate.registerSession(
          userId: jwt.sub,
          session: session,
          close: () => session.sender.close(4003, 'QA realtime suspended'),
        );
        session.send(_authLogInResponse);
        await _setPresenceStatus(jwt.sub, UserPresenceStatus.online);
        await broadcastPresenceForUser(jwt.sub);
        logger.info(
          '[WebsocketSessionHandlerBase] Start session: [${jwt.sub}]',
        );

      case AuthRequestIntent.cnameSignOut:
        final jwt = removeSession(session);
        if (jwt != null) {
          session.send(_authLogOutResponse);
          await _setPresenceStatus(jwt.sub, UserPresenceStatus.offline);
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
