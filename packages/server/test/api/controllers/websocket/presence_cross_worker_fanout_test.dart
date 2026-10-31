import 'dart:async';
import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:postgres/postgres.dart';
import 'package:shelf_plus/shelf_plus.dart' show WebSocketSession;
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/api/controllers/websocket_controller.dart';
import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/port/beacon_room_co_participant_lookup_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

import 'websocket_realtime_protocol_test.mocks.dart';

const _aliceId = 'Ua11ce0000001';
const _bobId = 'Ub0b000000001';

/// The offline grace period the test workers use instead of the 3 s default.
const _testGrace = Duration(milliseconds: 30);

/// #533: the server runs one web worker per isolate behind a shared port, so
/// a watcher and the person they watch are often on different workers. A
/// presence change has to reach watchers on every worker, the way Postgres
/// LISTEN/NOTIFY already carries entity changes between them.
void main() {
  group('presence fan-out across web workers (#533)', () {
    late _Cluster cluster;

    setUp(() async {
      cluster = _Cluster();
      addTearDown(cluster.dispose);
    });

    test(
      'a person opening the request on another worker lights the dot for a '
      'watcher on this worker',
      () async {
        final first = await cluster.worker();
        final second = await cluster.worker();
        final alice = _RecordingSession();
        await cluster.authenticate(first, alice, _aliceId);
        await first.sendPresenceSnapshotForPeers(alice, [_bobId]);
        alice.sent.clear();

        final bob = _RecordingSession();
        await cluster.authenticate(second, bob, _bobId);

        await _waitUntil(() => _lastStatusFor(alice, _bobId) != null);
        expect(_lastStatusFor(alice, _bobId), 'online');
      },
    );

    test(
      'a person closing their only tab on another worker clears the dot for '
      'a watcher on this worker',
      () async {
        final first = await cluster.worker();
        final second = await cluster.worker();
        final alice = _RecordingSession();
        final bob = _RecordingSession();
        await cluster.authenticate(first, alice, _aliceId);
        await cluster.authenticate(second, bob, _bobId);
        await first.sendPresenceSnapshotForPeers(alice, [_bobId]);
        expect(_lastStatusFor(alice, _bobId), 'online');
        alice.sent.clear();

        second.handler().onClose!(bob);

        // Wait for "offline" itself: Bob's sign-in "online" fan-out can still
        // reach Alice after the clear above, so "any frame" is not enough.
        await _waitUntil(() => _lastStatusFor(alice, _bobId) == 'offline');
        expect(cluster.presence.statuses[_bobId], UserPresenceStatus.offline);
      },
    );

    test(
      'closing an old tab after a new tab opened on another worker leaves '
      'the person online',
      () async {
        final first = await cluster.worker();
        final second = await cluster.worker();
        final alice = _RecordingSession();
        final oldTab = _RecordingSession();
        final newTab = _RecordingSession();
        await cluster.authenticate(first, alice, _aliceId);
        await cluster.authenticate(first, oldTab, _bobId);
        await first.sendPresenceSnapshotForPeers(alice, [_bobId]);
        await cluster.authenticate(second, newTab, _bobId);
        alice.sent.clear();

        first.handler().onClose!(oldTab);

        // Past the grace period, when "offline" would have been stored.
        await Future<void>.delayed(_testGrace * 4);
        expect(cluster.presence.statuses[_bobId], UserPresenceStatus.online);
        expect(_statusesFor(alice, _bobId), isNot(contains('offline')));
      },
    );

    test(
      'a new tab opening on another worker while the old tab closes never '
      'shows the person offline',
      () async {
        final first = await cluster.worker();
        final second = await cluster.worker();
        final alice = _RecordingSession();
        final oldTab = _RecordingSession();
        await cluster.authenticate(first, alice, _aliceId);
        await cluster.authenticate(first, oldTab, _bobId);
        await first.sendPresenceSnapshotForPeers(alice, [_bobId]);
        alice.sent.clear();

        // A reload: the old socket closes, the new one lands on another
        // worker a moment later.
        first.handler().onClose!(oldTab);
        await Future<void>.delayed(const Duration(milliseconds: 5));
        await cluster.authenticate(second, _RecordingSession(), _bobId);

        await Future<void>.delayed(_testGrace * 4);
        expect(cluster.presence.statuses[_bobId], UserPresenceStatus.online);
        expect(_statusesFor(alice, _bobId), isNot(contains('offline')));
      },
    );

    test(
      'an "online" repair that lands after the socket closed does not leave '
      'the person stuck online',
      () async {
        final worker = await cluster.worker();
        final alice = _RecordingSession();
        final bob = _RecordingSession();
        await cluster.authenticate(worker, alice, _aliceId);
        await cluster.authenticate(worker, bob, _bobId);
        await worker.sendPresenceSnapshotForPeers(alice, [_bobId]);
        alice.sent.clear();

        // Another worker stored "offline" while this one holds Bob's socket,
        // so this worker repairs it; the repair's write is slow to land.
        cluster.presence.statuses[_bobId] = UserPresenceStatus.offline;
        final release = cluster.presence.holdNextWrite(
          UserPresenceStatus.online,
        );
        unawaited(worker.fanOutPresenceLocally(_bobId));
        await _waitUntil(() => cluster.presence.heldWrites == 1);

        // Bob's socket closes while the "online" write is in flight.
        worker.handler().onClose!(bob);
        await Future<void>.delayed(_testGrace * 3);
        release.complete();
        await _waitUntil(() => cluster.presence.heldWrites == 0);
        await Future<void>.delayed(_testGrace * 3);

        expect(cluster.presence.statuses[_bobId], UserPresenceStatus.offline);
        expect(_lastStatusFor(alice, _bobId), 'offline');
      },
    );

    test(
      'presence missed while the LISTEN connection was down reaches watchers '
      'after it recovers',
      () async {
        final first = await cluster.worker(
          reconnectDelay: const Duration(milliseconds: 100),
        );
        final second = await cluster.worker();
        final alice = _RecordingSession();
        final bob = _RecordingSession();
        await cluster.authenticate(first, alice, _aliceId);
        await cluster.authenticate(second, bob, _bobId);
        await first.sendPresenceSnapshotForPeers(alice, [_bobId]);
        expect(_lastStatusFor(alice, _bobId), 'online');
        alice.sent.clear();

        // The first worker's LISTEN connection drops; Bob leaves meanwhile.
        cluster.bus.connections.first.failAndClose();
        second.handler().onClose!(bob);

        // Wait for "offline" itself: Bob's sign-in "online" fan-out can still
        // reach Alice after the clear above, so "any frame" is not enough.
        await _waitUntil(() => _lastStatusFor(alice, _bobId) == 'offline');
        expect(cluster.presence.statuses[_bobId], UserPresenceStatus.offline);
      },
    );

    test(
      'closing one of two tabs on the same worker does not show the person '
      'offline',
      () async {
        final worker = await cluster.worker();
        final alice = _RecordingSession();
        final firstTab = _RecordingSession();
        final secondTab = _RecordingSession();
        await cluster.authenticate(worker, alice, _aliceId);
        await cluster.authenticate(worker, firstTab, _bobId);
        await cluster.authenticate(worker, secondTab, _bobId);
        await worker.sendPresenceSnapshotForPeers(alice, [_bobId]);
        alice.sent.clear();

        worker.handler().onClose!(firstTab);
        await Future<void>.delayed(const Duration(milliseconds: 20));

        expect(cluster.presence.statuses[_bobId], UserPresenceStatus.online);
        expect(_lastStatusFor(alice, _bobId), anyOf(isNull, 'online'));
      },
    );
  });
}

/// The status of the last presence event for [userId] that [session] got.
String? _lastStatusFor(_RecordingSession session, String userId) {
  final statuses = _statusesFor(session, userId);
  return statuses.isEmpty ? null : statuses.last;
}

/// Every presence status for [userId] that [session] got, in order.
List<String> _statusesFor(_RecordingSession session, String userId) => [
  for (final raw in session.sent)
    if (jsonDecode(raw! as String) case {
      'path': 'user_presence',
      'payload': {'events': final List<dynamic> events},
    })
      for (final e in events.cast<Map<String, dynamic>>())
        if (e['user_id'] == userId) e['status'] as String,
];

Future<void> _waitUntil(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 1),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (!condition()) {
    if (DateTime.timestamp().isAfter(deadline)) {
      fail('Condition was not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

/// Several web workers sharing one database and one NOTIFY bus.
final class _Cluster {
  final env = Env.test();
  final logger = Logger('PresenceCrossWorkerFanoutTest');
  final presence = _InMemoryPresenceRepository();
  final bus = _NotifyBus();
  late final authCase = AuthCase(
    MockUserRepositoryPort(),
    MockInvitationRepositoryPort(),
    env: env,
    logger: logger,
  );
  final _workers = <WebSocketController>[];
  final _services = <PgNotificationService>[];

  Future<WebSocketController> worker({
    Duration reconnectDelay = Duration.zero,
  }) async {
    final notifications = await PgNotificationService.createForTesting(
      env,
      bus,
      reconnectDelay: reconnectDelay,
    );
    final controller = WebSocketController(
      env,
      logger,
      authCase,
      UserPresenceCase(presence, env: env, logger: logger),
      _EveryoneIsAFriend(),
      _EveryoneIsAFriend(),
      MockRoomMessageSnapshotLookupPort(),
      QaRealtimeSocketGate(),
      notifications,
      presenceOfflineGrace: _testGrace,
    );
    _services.add(notifications);
    _workers.add(controller);
    return controller;
  }

  Future<void> authenticate(
    WebSocketController worker,
    WebSocketSession session,
    String userId,
  ) => worker.onAuth(session, {
    'intent': AuthRequestIntent.cnameSignIn,
    'token': authCase.issueAccessToken(userId).rawToken,
  });

  Future<void> dispose() async {
    for (final w in _workers) {
      w.authenticatedSessions.forEach(w.removeSession);
      await w.dispose();
    }
    for (final s in _services) {
      await s.dispose();
    }
  }
}

final class _InMemoryPresenceRepository implements UserPresenceRepositoryPort {
  final statuses = <String, UserPresenceStatus>{};
  final _lastSeen = <String, DateTime>{};

  /// Writes started but not yet landed, see [holdNextWrite].
  int heldWrites = 0;
  UserPresenceStatus? _holdStatus;
  Completer<void>? _hold;

  /// Delays the next write of [status] until the returned completer
  /// completes, like a pooled DB write that lands after a later one.
  Completer<void> holdNextWrite(UserPresenceStatus status) {
    _holdStatus = status;
    return _hold = Completer<void>();
  }

  @override
  Future<UserPresenceEntity?> get(String userId) async {
    final status = statuses[userId];
    if (status == null) return null;
    return UserPresenceEntity(
      userId: userId,
      status: status,
      lastSeenAt: _lastSeen[userId]!,
      lastNotifiedAt: DateTime.fromMillisecondsSinceEpoch(0),
      offlineAfterDelay: const Duration(seconds: 30),
    );
  }

  @override
  Future<void> update(
    String userId, {
    DateTime? lastSeenAt,
    DateTime? lastNotifiedAt,
    UserPresenceStatus? status,
  }) async {
    final hold = _hold;
    if (hold != null && status == _holdStatus) {
      _hold = null;
      _holdStatus = null;
      heldWrites++;
      await hold.future;
      heldWrites--;
    }
    if (status != null) statuses[userId] = status;
    _lastSeen[userId] = lastSeenAt ?? _lastSeen[userId] ?? DateTime.timestamp();
  }
}

final class _EveryoneIsAFriend
    implements VoteUserFriendshipLookupPort, BeaconRoomCoParticipantLookupPort {
  @override
  Future<Set<String>> reciprocalPositivePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async => peerIds.toSet();

  @override
  Future<Set<String>> coParticipantPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async => peerIds.toSet();

  @override
  Future<Set<String>> roomMemberUserIds({required String beaconId}) async => {};

  @override
  Future<({Set<String> viewerTrusts, Set<String> trustsViewer})>
  directionalPositiveTrustPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async => (viewerTrusts: peerIds.toSet(), trustsViewer: peerIds.toSet());

  @override
  Future<bool> isReciprocalSubscribe({
    required String viewerId,
    required String peerId,
  }) async => true;

  @override
  Future<bool> isSubscribedTo({
    required String viewerId,
    required String peerId,
  }) async => true;
}

/// Postgres NOTIFY between connections: a payload sent on a channel reaches
/// every open connection that LISTENs on it, the sender's own included.
final class _NotifyBus implements PgNotificationConnector {
  final _connections = <_BusConnection>[];

  /// Every connection opened so far, oldest first.
  List<_BusConnection> get connections => List.unmodifiable(_connections);

  @override
  Future<PgNotificationConnection> open(
    Endpoint endpoint, {
    required ConnectionSettings settings,
  }) async {
    final connection = _BusConnection(this);
    _connections.add(connection);
    return connection;
  }

  void deliver(String channel, String payload) {
    for (final c in _connections) {
      if (!c.closed && c.listened.contains(channel)) {
        c.controllerFor(channel).add(payload);
      }
    }
  }
}

final class _BusConnection implements PgNotificationConnection {
  _BusConnection(this._bus);

  final _NotifyBus _bus;
  final _channels = <String, StreamController<String>>{};
  final listened = <String>{};
  bool closed = false;

  StreamController<String> controllerFor(String name) =>
      _channels[name] ??= StreamController<String>.broadcast();

  @override
  Stream<String> channel(String name) => controllerFor(name).stream;

  /// The LISTEN connection drops: nothing more reaches it, and the service
  /// sees the error and reconnects.
  void failAndClose() {
    closed = true;
    controllerFor('entity_changes').addError(StateError('connection lost'));
  }

  @override
  Future<void> listen(String channel) async => listened.add(channel);

  @override
  Future<void> notify(String channel, String payload) async =>
      // Delivered asynchronously, as Postgres does.
      scheduleMicrotask(() => _bus.deliver(channel, payload));

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _RecordingSession extends WebSocketSession {
  final sent = <Object?>[];

  @override
  void send(Object? data) => sent.add(data);
}
