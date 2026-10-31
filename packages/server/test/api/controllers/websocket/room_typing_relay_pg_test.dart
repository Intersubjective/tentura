@Tags(['pg'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:shelf_plus/shelf_plus.dart' show WebSocketSession;
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';

import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/api/controllers/websocket_controller.dart';
import 'package:tentura_server/consts/beacon_room_consts.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/beacon_room_co_participant_lookup.dart';
import 'package:tentura_server/data/service/pg_notification_connection.dart';
import 'package:tentura_server/data/service/pg_notification_service.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

import '../../../support/disposable_pg_target.dart';
import 'websocket_realtime_protocol_test.mocks.dart';

// Valid user ids: `U` plus twelve hex digits.
const _authorId = 'Ua0a0a0000001';
const _stewardId = 'Ub0b0b0000002';
const _admittedId = 'Uc0c0c0000003';
const _requestedId = 'Ud0d0d0000004';
const _invitedId = 'Ue0e0e0000005';
const _leftId = 'Uf0f0f0000006';
const _strangerId = 'Ua1a1a1000007';
const _beaconId = 'Btyping00001';

/// The typing relay authorised by the production membership query, with real
/// Postgres NOTIFY between two web workers. The wire contract is the one
/// documented in room_typing_relay_test.dart.
Future<void> main() async {
  final skipReason = !await canReachPostgresAdmin(_target);
  DisposablePgWriterSession? pgSession;
  if (!skipReason) {
    pgSession = await setUpDisposablePgWriter(target: _target);
    tearDownAll(() => tearDownDisposablePgWriter(session: pgSession!));
  }

  late TenturaDb db;
  late BeaconRoomCoParticipantLookup lookup;

  if (!skipReason) {
    setUpAll(() async {
      db = TenturaDb(_testEnv());
      lookup = BeaconRoomCoParticipantLookup(db);
      await _seedRoom(db);
    });

    // The database is disposable: no row cleanup needed.
    tearDownAll(() async {
      await db.close();
    });
  }

  test(
    'the Request room members are its author, stewards and admitted '
    'participants, and nobody who only asked, was invited or left',
    () async {
      // Called dynamically so this file compiles before the port has the
      // method; until then it fails as NoSuchMethodError.
      final members =
          await (lookup as dynamic).roomMemberUserIds(beaconId: _beaconId)
              as Set<String>;

      expect(members, {_authorId, _stewardId, _admittedId});
    },
    skip: skipReason ? 'Postgres not reachable' : false,
  );

  group('typing relay over the real membership query and real NOTIFY', () {
    late _Cluster cluster;

    setUp(() {
      cluster = _Cluster(lookup: () => lookup);
      addTearDown(cluster.dispose);
    });

    test(
      'a member is announced to the other members on another worker, and '
      'to nobody who is not in the room',
      () async {
        final first = await cluster.worker();
        final second = await cluster.worker();
        final author = _RecordingSession();
        final steward = _RecordingSession();
        final admitted = _RecordingSession();
        final requested = _RecordingSession();
        final invited = _RecordingSession();
        final left = _RecordingSession();
        final stranger = _RecordingSession();
        await cluster.authenticate(first, author, _authorId);
        await cluster.authenticate(second, steward, _stewardId);
        await cluster.authenticate(second, admitted, _admittedId);
        await cluster.authenticate(second, requested, _requestedId);
        await cluster.authenticate(second, invited, _invitedId);
        await cluster.authenticate(second, left, _leftId);
        await cluster.authenticate(second, stranger, _strangerId);
        cluster.clearAll();

        await cluster.typing(first, author, 'start', _beaconId);
        await _waitUntil(
          () =>
              _typingFrames(steward).isNotEmpty &&
              _typingFrames(admitted).isNotEmpty,
          timeout: const Duration(seconds: 3),
        );
        await Future<void>.delayed(const Duration(milliseconds: 200));

        const expected = {
          'beacon_id': _beaconId,
          'user_id': _authorId,
          'typing': true,
        };
        expect(_typingFrames(steward), [expected]);
        expect(_typingFrames(admitted), [expected]);
        expect(_typingFrames(author), isEmpty);
        for (final s in [requested, invited, left, stranger]) {
          expect(_typingFrames(s), isEmpty);
        }
      },
    );

    test(
      'a steward and an admitted participant may type; a requester, an '
      'invitee, someone who left and a stranger are refused',
      () async {
        final worker = await cluster.worker();
        final author = _RecordingSession();
        final steward = _RecordingSession();
        final admitted = _RecordingSession();
        final refused = {
          for (final id in [_requestedId, _invitedId, _leftId, _strangerId])
            id: _RecordingSession(),
        };
        await cluster.authenticate(worker, author, _authorId);
        await cluster.authenticate(worker, steward, _stewardId);
        await cluster.authenticate(worker, admitted, _admittedId);
        for (final e in refused.entries) {
          await cluster.authenticate(worker, e.value, e.key);
        }
        cluster.clearAll();

        for (final session in refused.values) {
          await cluster.typing(worker, session, 'start', _beaconId);
        }
        await _settle();

        expect(_typingFrames(author), isEmpty);
        expect(_typingFrames(steward), isEmpty);
        expect(_typingFrames(admitted), isEmpty);
        for (final session in refused.values) {
          expect(session.sent.where(_isErrorFrame), hasLength(1));
        }

        await cluster.typing(worker, steward, 'start', _beaconId);
        await cluster.typing(worker, admitted, 'start', _beaconId);
        await _settle();

        expect(
          _typingFrames(author).map((f) => f['user_id']),
          unorderedEquals([_stewardId, _admittedId]),
        );
        expect(_typingFrames(admitted).map((f) => f['user_id']), [_stewardId]);
        expect(_typingFrames(steward).map((f) => f['user_id']), [_admittedId]);
      },
    );
  });
}

final _allUserIds = [
  _authorId,
  _stewardId,
  _admittedId,
  _requestedId,
  _invitedId,
  _leftId,
  _strangerId,
];

Future<void> _seedRoom(TenturaDb db) async {
  var n = 0;
  for (final id in _allUserIds) {
    n++;
    await db.customStatement(
      r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES ($1, $2, $3, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
      [id, 'Typist $n', '${String.fromCharCode(96 + n) * 43}$n'],
    );
  }
  // Published and open, as a live Request room is. The author has no
  // participant row on purpose.
  await db.customStatement(
    '''
INSERT INTO public.beacon
  (id, user_id, title, description, status, published_at, created_at, updated_at)
VALUES ('$_beaconId', '$_authorId', 'Typing room', 'Typing room', 1,
  '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
ON CONFLICT (id) DO NOTHING
''',
  );
  await db.customStatement(
    '''
INSERT INTO public.beacon_steward (beacon_id, user_id)
VALUES ('$_beaconId', '$_stewardId')
''',
  );
  await db.customStatement(
    '''
INSERT INTO public.beacon_participant
  (id, beacon_id, user_id, role, status, room_access, created_at, updated_at)
VALUES
  ('Ptyping00003', '$_beaconId', '$_admittedId', 2, 0, ${RoomAccessBits.admitted},
    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ptyping00004', '$_beaconId', '$_requestedId', 2, 0, ${RoomAccessBits.requested},
    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ptyping00005', '$_beaconId', '$_invitedId', 2, 0, ${RoomAccessBits.invited},
    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z'),
  ('Ptyping00006', '$_beaconId', '$_leftId', 2, 0, ${RoomAccessBits.left},
    '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
''',
  );
}

/// Lets in-flight NOTIFY deliveries and async handlers finish.
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 300));

bool _isErrorFrame(Object? raw) {
  final frame = jsonDecode(raw! as String);
  return frame is Map && frame.containsKey('error');
}

List<Map<String, dynamic>> _typingFrames(_RecordingSession session) => [
  for (final raw in session.sent)
    if (jsonDecode(raw! as String) case {
      'type': 'subscription',
      'path': 'room_typing',
      'payload': final Map<String, dynamic> payload,
    })
      payload,
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
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

/// Web workers on the real database and the real Postgres LISTEN/NOTIFY.
final class _Cluster {
  _Cluster({required this.lookup});

  final BeaconRoomCoParticipantLookup Function() lookup;
  final env = _testEnv();
  final logger = Logger('RoomTypingRelayPgTest');
  late final authCase = AuthCase(
    MockUserRepositoryPort(),
    MockInvitationRepositoryPort(),
    env: env,
    logger: logger,
  );
  final _workers = <WebSocketController>[];
  final _services = <PgNotificationService>[];
  final _sessions = <_RecordingSession>[];
  final _presence = _InMemoryPresenceRepository();

  Future<WebSocketController> worker() async {
    final notifications = await PgNotificationService.createForTesting(
      env,
      const PostgresNotificationConnector(),
    );
    final controller = WebSocketController(
      env,
      logger,
      authCase,
      UserPresenceCase(_presence, env: env, logger: logger),
      _NoFriends(),
      lookup(),
      MockRoomMessageSnapshotLookupPort(),
      QaRealtimeSocketGate(),
      notifications,
    );
    _services.add(notifications);
    _workers.add(controller);
    return controller;
  }

  Future<void> authenticate(
    WebSocketController worker,
    _RecordingSession session,
    String userId,
  ) async {
    _sessions.add(session);
    await worker.onAuth(session, {
      'intent': AuthRequestIntent.cnameSignIn,
      'token': authCase.issueAccessToken(userId).rawToken,
    });
  }

  void clearAll() {
    for (final s in _sessions) {
      s.sent.clear();
    }
  }

  Future<void> typing(
    WebSocketController worker,
    _RecordingSession session,
    String intent,
    String beaconId,
  ) => worker.onTextMessage(
    session,
    jsonEncode({
      'type': 'message',
      'path': 'room_typing',
      'payload': {'intent': intent, 'beacon_id': beaconId},
    }),
  );

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

final class _NoFriends implements VoteUserFriendshipLookupPort {
  @override
  Future<Set<String>> reciprocalPositivePeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async => {};

  @override
  Future<({Set<String> viewerTrusts, Set<String> trustsViewer})>
  directionalPositiveTrustPeerIds({
    required String viewerId,
    required Iterable<String> peerIds,
  }) async => (viewerTrusts: <String>{}, trustsViewer: <String>{});

  @override
  Future<bool> isReciprocalSubscribe({
    required String viewerId,
    required String peerId,
  }) async => false;

  @override
  Future<bool> isSubscribedTo({
    required String viewerId,
    required String peerId,
  }) async => false;
}

final class _InMemoryPresenceRepository implements UserPresenceRepositoryPort {
  final _statuses = <String, UserPresenceStatus>{};

  @override
  Future<UserPresenceEntity?> get(String userId) async {
    final status = _statuses[userId];
    if (status == null) return null;
    return UserPresenceEntity(
      userId: userId,
      status: status,
      lastSeenAt: DateTime.timestamp(),
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
    if (status != null) _statuses[userId] = status;
  }
}

final class _RecordingSession extends WebSocketSession {
  final sent = <Object?>[];

  @override
  void send(Object? data) => sent.add(data);
}

final _target = DisposablePgTarget.fromNamedEnvironment(
  envVarName: 'TENTURA_ROOM_TYPING_RELAY_TEST_DB',
  defaultNamePrefix: 'tentura_test_room_typing',
);

Env _testEnv() => Env(
  environment: Environment.test,
  pgHost: Platform.environment['POSTGRES_HOST'] ?? '127.0.0.1',
  pgPort: int.tryParse(Platform.environment['POSTGRES_PORT'] ?? '') ?? 5432,
  pgDatabase: _target.databaseName,
  pgPassword: Platform.environment['POSTGRES_PASSWORD'] ?? 'password',
  printEnv: false,
  isDebugModeOn: false,
  logLevel: Level.WARNING,
  workersCount: 1,
);
