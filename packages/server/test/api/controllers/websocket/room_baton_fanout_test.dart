import 'dart:convert';

import 'package:logging/logging.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import 'package:tentura_root/domain/entity/auth_request_intent.dart';
import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/api/controllers/websocket/path_handler/websocket_path_entity_changes.dart';
import 'package:tentura_server/api/controllers/websocket/session/qa_realtime_socket_gate.dart';
import 'package:tentura_server/api/controllers/websocket/session/websocket_session_handler_base.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/port/beacon_room_co_participant_lookup_port.dart';
import 'package:tentura_server/domain/port/invitation_repository_port.dart';
import 'package:tentura_server/domain/port/room_message_snapshot_lookup_port.dart';
import 'package:tentura_server/domain/port/user_presence_repository_port.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/auth_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/env.dart';

const _authorId = 'Ua00000000001';
const _candidateId = 'Uc00000000001';
const _otherCandidateId = 'Uc00000000002';
const _observerId = 'Ud00000000001';
const _beaconId = 'Bbeacon000001';

void main() {
  group('room_baton realtime fan-out', () {
    test('reaches only the users listed on the notification', () async {
      final dependencies = _Dependencies();
      final handler = _Harness(Env(realtimeActorEchoEnabled: true), dependencies);
      final author = _RecordingSession();
      final candidate = _RecordingSession();
      final otherCandidate = _RecordingSession();
      final observer = _RecordingSession();
      await dependencies.authenticate(handler, author, _authorId);
      await dependencies.authenticate(handler, candidate, _candidateId);
      await dependencies.authenticate(
        handler,
        otherCandidate,
        _otherCandidateId,
      );
      await dependencies.authenticate(handler, observer, _observerId);
      for (final s in [author, candidate, otherCandidate, observer]) {
        s.sent.clear();
      }

      await handler.fanOutEntityChange({
        'entity': 'room_baton',
        'id': _beaconId,
        'event': 'update',
        'actor_user_id': _candidateId,
        'user_ids': [_authorId, _candidateId],
      });

      expect(author.sent, hasLength(1));
      expect(candidate.sent, hasLength(1));
      expect(otherCandidate.sent, isEmpty);
      expect(observer.sent, isEmpty);
    });

    test('frame names the room and event without leaking recipients',
        () async {
      final dependencies = _Dependencies();
      final handler = _Harness(Env(realtimeActorEchoEnabled: true), dependencies);
      final candidate = _RecordingSession();
      await dependencies.authenticate(handler, candidate, _candidateId);
      candidate.sent.clear();

      await handler.fanOutEntityChange({
        'entity': 'room_baton',
        'id': _beaconId,
        'event': 'insert',
        'actor_user_id': _authorId,
        'user_ids': [_authorId, _candidateId, _otherCandidateId],
      });

      final frame = jsonDecode(candidate.sent.single! as String) as Map;
      expect(frame['path'], 'entity_changes');
      final payload = frame['payload'] as Map;
      expect(payload['entity'], 'room_baton');
      expect(payload['id'], _beaconId);
      expect(payload['event'], 'insert');
      expect(payload.containsKey('user_ids'), isFalse);
      expect(payload.containsKey('message'), isFalse);
    });

    test('every session of a listed user receives the notification', () async {
      final dependencies = _Dependencies();
      final handler = _Harness(Env(realtimeActorEchoEnabled: true), dependencies);
      final first = _RecordingSession();
      final second = _RecordingSession();
      await dependencies.authenticate(handler, first, _candidateId);
      await dependencies.authenticate(handler, second, _candidateId);
      first.sent.clear();
      second.sent.clear();

      await handler.fanOutEntityChange({
        'entity': 'room_baton',
        'id': _beaconId,
        'event': 'update',
        'actor_user_id': _authorId,
        'user_ids': [_candidateId],
      });

      expect(first.sent, hasLength(1));
      expect(second.sent, hasLength(1));
    });

    test('actor echo does not add an acting user who is not listed',
        () async {
      final dependencies = _Dependencies();
      final handler = _Harness(Env(realtimeActorEchoEnabled: true), dependencies);
      final actor = _RecordingSession();
      final author = _RecordingSession();
      await dependencies.authenticate(handler, actor, _candidateId);
      await dependencies.authenticate(handler, author, _authorId);
      actor.sent.clear();
      author.sent.clear();

      await handler.fanOutEntityChange({
        'entity': 'room_baton',
        'id': _beaconId,
        'event': 'update',
        'actor_user_id': _candidateId,
        'user_ids': [_authorId],
      });

      expect(actor.sent, isEmpty);
      expect(author.sent, hasLength(1));
    });

    test('a user outside the list stays unnotified with echo disabled',
        () async {
      final dependencies = _Dependencies();
      final handler = _Harness(
        Env(realtimeActorEchoEnabled: false),
        dependencies,
      );
      final observer = _RecordingSession();
      final author = _RecordingSession();
      await dependencies.authenticate(handler, observer, _observerId);
      await dependencies.authenticate(handler, author, _authorId);
      observer.sent.clear();
      author.sent.clear();

      await handler.fanOutEntityChange({
        'entity': 'room_baton',
        'id': _beaconId,
        'event': 'update',
        'actor_user_id': _candidateId,
        'user_ids': [_authorId, _candidateId],
      });

      expect(observer.sent, isEmpty);
      expect(author.sent, hasLength(1));
    });
  });
}

final class _Dependencies {
  _Dependencies() {
    final logger = Logger('RoomBatonFanoutTest');
    authCase = AuthCase(
      _UnusedUserRepository(),
      _UnusedInvitationRepository(),
      env: env,
      logger: logger,
    );
    userPresenceCase = UserPresenceCase(
      _FakePresenceRepository(),
      env: env,
      logger: logger,
    );
  }

  final env = Env.test();
  late final AuthCase authCase;
  late final UserPresenceCase userPresenceCase;
  final qaRealtimeSocketGate = QaRealtimeSocketGate();
  final friendshipLookup = _FakeFriendshipLookup();
  final coParticipantLookup = _FakeCoParticipantLookup();
  final roomMessageSnapshotLookup = _FakeSnapshotLookup();

  Future<void> authenticate(
    WebsocketSessionHandlerBase handler,
    WebSocketSession session,
    String userId,
  ) async {
    final token = authCase.issueAccessToken(userId).rawToken;
    await handler.onAuth(session, {
      'intent': AuthRequestIntent.cnameSignIn,
      'token': token,
    });
  }
}

final class _Harness extends WebsocketSessionHandlerBase
    with WebsocketPathEntityChanges {
  _Harness(Env env, _Dependencies dependencies)
    : super(
        env,
        Logger('RoomBatonFanoutHarness'),
        dependencies.authCase,
        dependencies.userPresenceCase,
        dependencies.friendshipLookup,
        dependencies.coParticipantLookup,
        dependencies.roomMessageSnapshotLookup,
        dependencies.qaRealtimeSocketGate,
      );
}

final class _RecordingSession extends WebSocketSession {
  final sent = <Object?>[];

  @override
  void send(Object? data) => sent.add(data);
}

final class _UnusedUserRepository extends Fake implements UserRepositoryPort {}

final class _UnusedInvitationRepository extends Fake
    implements InvitationRepositoryPort {}

final class _FakePresenceRepository implements UserPresenceRepositoryPort {
  @override
  Future<UserPresenceEntity?> get(String userId) async => null;

  @override
  Future<void> update(
    String userId, {
    DateTime? lastSeenAt,
    DateTime? lastNotifiedAt,
    UserPresenceStatus? status,
  }) async {}
}

final class _FakeFriendshipLookup extends Fake
    implements VoteUserFriendshipLookupPort {}

final class _FakeCoParticipantLookup extends Fake
    implements BeaconRoomCoParticipantLookupPort {}

final class _FakeSnapshotLookup extends Fake
    implements RoomMessageSnapshotLookupPort {}
