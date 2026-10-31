// A real `RemoteApiService` (real auth handshake, real frame parsing) and a
// real `BeaconThreadsRepository` over it; only the socket and the HTTP token
// endpoint are faked. Typing tests use it to prove frames travel the
// production path: socket frame -> RemoteApiClientWs -> repository -> case ->
// cubit -> widget, and composer edits -> cubit -> repository -> socket frame.

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/room_typing_signal.dart';

import '../room_cubit_fakes.dart';

const roomTypingWireViewerId = 'Uviewer000001';

/// The socket the app talks to: the test pushes server frames into
/// `frames`, and [sent] records what the app sent.
final class RoomTypingWireSocket implements RealtimeSocket {
  final connections =
      StreamController<RealtimeSocketConnectionState>.broadcast();
  final frames = StreamController<Object?>.broadcast();
  final sent = <Object>[];

  @override
  Stream<RealtimeSocketConnectionState> get connection => connections.stream;

  @override
  Stream<Object?> get messages => frames.stream;

  @override
  void send(Object message) => sent.add(message);

  @override
  Future<void> close() async {
    await connections.close();
    await frames.close();
  }

  /// Every `room_typing` message the app sent, decoded, in order.
  List<Map<String, dynamic>> get typingFramesSent => [
    for (final raw in sent)
      if (raw is String)
        if (jsonDecode(raw) case final Map<String, dynamic> frame
            when frame['path'] == 'room_typing')
          frame,
  ];
}

final class _SocketFactory implements RealtimeSocketFactory {
  _SocketFactory(this.socket);

  final RoomTypingWireSocket socket;

  @override
  RealtimeSocket create(Uri uri) => socket;
}

/// The production typing stack for one signed-in viewer.
final class RoomTypingWire {
  RoomTypingWire._(this.socket, this.remote, this.realtime, this.repository);

  final RoomTypingWireSocket socket;
  final RemoteApiService remote;
  final InvalidationService realtime;

  /// The real repository, as DI builds it.
  final BeaconThreadsRepository repository;

  /// Signs the viewer in over the fake socket. Call inside
  /// `tester.runAsync` in widget tests: the handshake needs real time.
  static Future<RoomTypingWire> start() => http.runWithClient(() async {
    final socket = RoomTypingWireSocket();
    final remote = RemoteApiService(const Env(), _SocketFactory(socket));
    final realtime = InvalidationService(remote);
    final repository = BeaconThreadsRepository(remote, realtime);
    final wire = RoomTypingWire._(socket, remote, realtime, repository);
    await remote.setSessionAuth();
    await remote.bindRealtimeAccount(roomTypingWireViewerId);
    socket.connections.add(RealtimeSocketConnectionState.connected);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    socket.frames.add(
      jsonEncode({'type': 'auth', 'intent': 'sign_in', 'result': 'success'}),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    return wire;
  }, () => MockClient(_serveToken));

  /// What the server pushes to this viewer for a member's typing.
  void relayFromServer({
    required String beaconId,
    required String userId,
    required bool typing,
  }) => socket.frames.add(
    jsonEncode({
      'type': 'subscription',
      'path': 'room_typing',
      'payload': {'beacon_id': beaconId, 'user_id': userId, 'typing': typing},
    }),
  );

  /// Any other server frame, verbatim.
  void receiveRaw(Object? frame) => socket.frames.add(jsonEncode(frame));

  Future<void> close() async {
    await repository.dispose();
    await realtime.dispose();
    await remote.close();
  }
}

Future<http.Response> _serveToken(http.Request request) async {
  if (request.url.path.endsWith('/session/access-token')) {
    return http.Response(
      jsonEncode({
        'subject': roomTypingWireViewerId,
        'access_token': 'test-token',
        'expires_in': 3600,
      }),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
  return http.Response('not served in this test', 500);
}

/// The room's fake data source (messages, participants, ...), whose viewer is
/// the account the socket is signed in as ([roomTypingWireViewerId]), with
/// typing taken from the real [BeaconThreadsRepository], so a room built on it
/// receives and sends typing exactly as in production.
class RoomOverRealTypingRepository extends FakeBeaconThreadsRepository {
  RoomOverRealTypingRepository(this._real)
    : super(userId: roomTypingWireViewerId);

  final BeaconThreadsRepository _real;

  @override
  Stream<RoomTypingSignal> get roomTypingSignals => _real.roomTypingSignals;

  @override
  void sendRoomTyping({required String beaconId, required bool typing}) =>
      _real.sendRoomTyping(beaconId: beaconId, typing: typing);
}

/// Lets a test wait for frames to cross the real stack.
Future<void> settleRoomTypingWire(WidgetTester tester) => tester
    .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)))
    .then((_) => tester.pump());
