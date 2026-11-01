// A real `RemoteApiService` (real auth handshake, real socket frame parsing,
// real Ferry link chain), the real `InvalidationService` and a real
// `BeaconThreadsRepository` over them; only the socket and the HTTP transport
// are faked. Live-hint tests use it to prove a server `entity_changes` frame
// travels the production path: socket frame -> InvalidationService ->
// BeaconThreadsRepository -> BeaconThreadsCase -> RoomCubit -> widget, and
// that the refetch the hint triggers goes over the real GraphQL mapping.

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';

import '../room_cubit_fakes.dart';
import 'room_typing_wire_harness.dart' show RoomTypingWireSocket;

const roomHintWireViewerId = 'Uviewer000001';

/// The fake backend: answers the GraphQL root fields the room refetches on a
/// hint from mutable state, so a test can change what the server reports
/// between the first load and the hint.
final class RoomHintWireServer {
  /// `RoomMessageList` rows, as the server's `v2_RoomMessageRow` type.
  List<Map<String, dynamic>> messageRows = [];

  /// `BeaconRoomReadWatermarks` rows, as `v2_v2_RoomReadWatermark`.
  List<Map<String, dynamic>> watermarkRows = [];

  /// Root fields of every GraphQL request received, in order.
  final queried = <String>[];

  Future<http.Response> serve(http.Request request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return _json({
        'subject': roomHintWireViewerId,
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final query = body['query'] as String? ?? '';
    if (query.contains('RoomMessageList(')) {
      queried.add('RoomMessageList');
      return _json({
        'data': {'RoomMessageList': messageRows},
      });
    }
    if (query.contains('BeaconRoomReadWatermarks(')) {
      queried.add('BeaconRoomReadWatermarks');
      return _json({
        'data': {'BeaconRoomReadWatermarks': watermarkRows},
      });
    }
    queried.add('unserved');
    return _json({
      'data': null,
      'errors': [
        {'message': 'not served in this test'},
      ],
    });
  }

  static http.Response _json(Object body) => http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

/// One `RoomMessageList` row with every field the client selects.
Map<String, dynamic> roomHintWireMessageRow({
  required String id,
  required String authorId,
  required String authorTitle,
  required String createdAt,
  String body = '',
  String? linkedPollingId,
  String? pollDataJson,
}) => {
  '__typename': 'v2_RoomMessageRow',
  'id': id,
  'beaconId': kRoomCubitFakeBeaconId,
  'authorId': authorId,
  'body': body,
  'createdAt': createdAt,
  'editedAt': null,
  'semanticMarker': null,
  'systemMessageKind': null,
  'linkedBlockerId': null,
  'linkedFactCardId': null,
  'linkedPollingId': linkedPollingId,
  'linkedItemId': null,
  'linkedEventKind': null,
  'linkedItemKind': null,
  'linkedItemStatus': null,
  'linkedItemTitle': null,
  'linkedItemBody': null,
  'linkedItemCreatorId': null,
  'linkedItemTargetPersonId': null,
  'linkedItemCreatedAt': null,
  'linkedItemUpdatedAt': null,
  'linkedItemLinkedMessageId': null,
  'linkedItemResolvedAt': null,
  'pollDataJson': pollDataJson,
  'batonDataJson': null,
  'systemPayloadJson': null,
  'authorTitle': authorTitle,
  'authorHasPicture': false,
  'authorPicHeight': 0,
  'authorPicWidth': 0,
  'authorBlurHash': '',
  'authorImageId': '',
  'reactionsJson': null,
  'myReaction': null,
  'reactorsJson': null,
  'attachmentsJson': '[]',
  'mentions': <String>[],
  'mentionSpansJson': '[]',
  'replyToAuthorId': null,
  'replyToAuthorTitle': null,
  'replyToBodyExcerpt': null,
  'replyToHasAttachments': false,
  'replyToMessageId': null,
  'threadItemId': null,
  'quotedFact': null,
};

final class _SocketFactory implements RealtimeSocketFactory {
  _SocketFactory(this.socket);

  final RoomTypingWireSocket socket;

  @override
  RealtimeSocket create(Uri uri) => socket;
}

/// The production realtime + room stack for one signed-in viewer.
final class RoomHintWire {
  RoomHintWire._(this.socket, this.remote, this.realtime, this.repository);

  final RoomTypingWireSocket socket;
  final RemoteApiService remote;
  final InvalidationService realtime;

  /// The real repository, as DI builds it.
  final BeaconThreadsRepository repository;

  /// Signs the viewer in over the fake socket; GraphQL goes to [server].
  /// Call inside `tester.runAsync` in widget tests: the handshake needs real
  /// time.
  static Future<RoomHintWire> start(RoomHintWireServer server) =>
      http.runWithClient(() async {
        final socket = RoomTypingWireSocket();
        final remote = RemoteApiService(const Env(), _SocketFactory(socket));
        final realtime = InvalidationService(remote);
        final repository = BeaconThreadsRepository(remote, realtime);
        final wire = RoomHintWire._(socket, remote, realtime, repository);
        await remote.setSessionAuth();
        await remote.bindRealtimeAccount(roomHintWireViewerId);
        socket.connections.add(RealtimeSocketConnectionState.connected);
        await Future<void>.delayed(const Duration(milliseconds: 20));
        socket.frames.add(
          jsonEncode({
            'type': 'auth',
            'intent': 'sign_in',
            'result': 'success',
          }),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
        return wire;
      }, () => MockClient(server.serve));

  /// The `entity_changes` frame the server sends for a room poll vote
  /// (wire entity `room_poll`, aggregate id = the Request id).
  void pushPollVote({String beaconId = kRoomCubitFakeBeaconId}) =>
      socket.frames.add(
        jsonEncode({
          'type': 'subscription',
          'path': 'entity_changes',
          'payload': {
            'entity': 'room_poll',
            'id': beaconId,
            'event': 'insert',
            'actor_user_id': null,
          },
        }),
      );

  /// The `entity_changes` frame the server sends when [seenUserId] reads the
  /// Request chat through [lastSeenAt] (wire entity `room_seen_peer`).
  void pushSeenPeer({
    required String seenUserId,
    required DateTime lastSeenAt,
    String beaconId = kRoomCubitFakeBeaconId,
  }) => socket.frames.add(
    jsonEncode({
      'type': 'subscription',
      'path': 'entity_changes',
      'payload': {
        'entity': 'room_seen_peer',
        'id': beaconId,
        'event': 'update',
        'actor_user_id': seenUserId,
        'seen_user_id': seenUserId,
        'last_seen_at': lastSeenAt.toUtc().toIso8601String(),
      },
    }),
  );

  Future<void> close() async {
    await repository.dispose();
    await realtime.dispose();
    await remote.close();
  }
}

/// The room's fake data source for everything a live hint does not touch
/// (participants, room state, facts, ...), whose viewer is the account the
/// socket is signed in as. Room invalidations, the message list and the read
/// watermarks come from the real [BeaconThreadsRepository], so a hint and the
/// refetch it triggers run exactly as in production.
class RoomOverRealHintWireRepository extends FakeBeaconThreadsRepository {
  RoomOverRealHintWireRepository(this._real)
    : super(userId: roomHintWireViewerId);

  final BeaconThreadsRepository _real;

  @override
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _real.beaconRoomInvalidations;

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) {
    fetchMessagesCallCount++;
    return _real.fetchMessages(
      beaconId: beaconId,
      beforeIso: beforeIso,
      threadItemId: threadItemId,
    );
  }

  @override
  Future<List<RoomReadWatermark>> fetchMainRoomReadWatermarks(
    String beaconId,
  ) {
    fetchMainRoomReadWatermarksCallCount++;
    return _real.fetchMainRoomReadWatermarks(beaconId);
  }
}
