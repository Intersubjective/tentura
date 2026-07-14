import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:ferry/ferry.dart' show OperationRequest, OperationResponse;
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/data/service/remote_api_client/credentials.dart';
import 'package:tentura/data/service/remote_api_client/realtime_socket.dart';
import 'package:tentura/data/service/remote_api_client/realtime_transport_status.dart';
import 'package:tentura/data/service/remote_api_client/remote_api_client_base.dart';
import 'package:tentura/data/service/remote_api_client/remote_api_client_ws.dart';

const _accountA = 'account-a';
const _accountB = 'account-b';

String get _seed => base64Encode(Uint8List(32));

Credentials _credentials(String accountId) => Credentials(
  userId: accountId,
  accessToken: 'token-$accountId',
  expiresAt: DateTime.timestamp().add(const Duration(hours: 1)),
);

Future<void> _settle([
  Duration delay = const Duration(milliseconds: 10),
]) async {
  await Future<void>.delayed(delay);
}

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

void _acceptAuthentication(_FakeRealtimeSocket socket) {
  socket.addMessage(
    jsonEncode({
      'type': 'auth',
      'intent': 'sign_in',
      'result': 'success',
    }),
  );
}

void main() {
  group('RemoteApiClientWs', () {
    test('opens no socket until an authoritative account is bound', () async {
      final factory = _FakeRealtimeSocketFactory();
      final client = _TestRealtimeClient(factory);
      addTearDown(client.close);

      await client.setAuth(
        seed: _seed,
        authTokenFetcher: (_, _) async => _credentials(_accountA),
      );
      expect(factory.sockets, isEmpty);

      await client.bindRealtimeAccount(_accountA);
      expect(factory.sockets, hasLength(1));
      expect(factory.sockets.single.sent, isEmpty);

      factory.sockets.single.addConnection(
        RealtimeSocketConnectionState.connected,
      );
      await _waitUntil(() => factory.sockets.single.sent.isNotEmpty);
      expect(
        jsonDecode(factory.sockets.single.sent.single as String),
        containsPair('token', 'token-account-a'),
      );
    });

    test('retries a token failure and reaches authenticated state', () async {
      final factory = _FakeRealtimeSocketFactory();
      final client = _TestRealtimeClient(factory);
      addTearDown(client.close);
      var tokenCalls = 0;
      await client.setAuth(
        seed: _seed,
        authTokenFetcher: (_, _) async {
          tokenCalls++;
          if (tokenCalls == 1) throw StateError('temporary token failure');
          return _credentials(_accountA);
        },
      );

      final statuses = <RealtimeTransportStatus>[];
      final statusSub = client.realtimeTransportStatus.listen(statuses.add);
      addTearDown(statusSub.cancel);
      await client.bindRealtimeAccount(_accountA);
      final socket = factory.sockets.single
        ..addConnection(RealtimeSocketConnectionState.connected);
      await _waitUntil(() => tokenCalls == 2 && socket.sent.isNotEmpty);

      expect(tokenCalls, 2);
      expect(socket.sent, hasLength(1));
      _acceptAuthentication(socket);
      await _settle();
      expect(statuses.last.phase, RealtimeTransportPhase.authenticated);
    });

    test('retries a server auth error without parking the socket', () async {
      final factory = _FakeRealtimeSocketFactory();
      final client = _TestRealtimeClient(factory);
      addTearDown(client.close);
      await client.setAuth(
        seed: _seed,
        authTokenFetcher: (_, _) async => _credentials(_accountA),
      );
      await client.bindRealtimeAccount(_accountA);
      final socket = factory.sockets.single
        ..addConnection(RealtimeSocketConnectionState.connected);
      await _waitUntil(() => socket.sent.isNotEmpty);
      expect(socket.sent, hasLength(1));

      socket.addMessage(jsonEncode({'error': 'invalid token'}));
      await _waitUntil(() => socket.sent.length == 2);
      expect(socket.sent, hasLength(2));
      _acceptAuthentication(socket);
      await _settle();

      expect(
        await client.realtimeTransportStatus.first,
        isA<RealtimeTransportStatus>().having(
          (status) => status.phase,
          'phase',
          RealtimeTransportPhase.authenticated,
        ),
      );
    });

    test('replaces a socket whose connection stream terminates', () async {
      final factory = _FakeRealtimeSocketFactory();
      final client = _TestRealtimeClient(factory);
      addTearDown(client.close);
      await client.setAuth(
        seed: _seed,
        authTokenFetcher: (_, _) async => _credentials(_accountA),
      );
      await client.bindRealtimeAccount(_accountA);
      final first = factory.sockets.single
        ..addConnection(RealtimeSocketConnectionState.connected);
      await _waitUntil(() => first.sent.isNotEmpty);
      _acceptAuthentication(first);
      await _settle();

      await first.finishConnection();
      await _waitUntil(() => factory.sockets.length == 2);
      expect(factory.sockets, hasLength(2));
      expect(first.closed, isTrue);

      final replacement = factory.sockets.last
        ..addConnection(RealtimeSocketConnectionState.connected);
      await _waitUntil(() => replacement.sent.isNotEmpty);
      expect(replacement.sent, hasLength(1));
    });

    test(
      'late frames from a previous account cannot authenticate it',
      () async {
        final factory = _FakeRealtimeSocketFactory();
        final client = _TestRealtimeClient(factory);
        addTearDown(client.close);
        await client.setAuth(
          seed: _seed,
          authTokenFetcher: (_, _) async => _credentials(_accountA),
        );

        final statuses = <RealtimeTransportStatus>[];
        final statusSub = client.realtimeTransportStatus.listen(statuses.add);
        addTearDown(statusSub.cancel);
        await client.bindRealtimeAccount(_accountA);
        final first = factory.sockets.single
          ..addConnection(RealtimeSocketConnectionState.connected);
        await _waitUntil(() => first.sent.isNotEmpty);

        await client.setAuth(
          seed: _seed,
          authTokenFetcher: (_, _) async => _credentials(_accountB),
        );
        await client.bindRealtimeAccount(_accountB);
        first.addMessage(
          jsonEncode({
            'type': 'auth',
            'intent': 'sign_in',
            'result': 'success',
          }),
        );
        await _settle();

        expect(client.realtimeAccountId, _accountB);
        expect(
          statuses.where(
            (status) =>
                status.accountId == _accountA &&
                status.phase == RealtimeTransportPhase.authenticated,
          ),
          isEmpty,
        );
      },
    );

    test(
      'ignores binary and malformed frames without closing streams',
      () async {
        final factory = _FakeRealtimeSocketFactory();
        final client = _TestRealtimeClient(factory);
        addTearDown(client.close);
        await client.setAuth(
          seed: _seed,
          authTokenFetcher: (_, _) async => _credentials(_accountA),
        );
        await client.bindRealtimeAccount(_accountA);
        final socket = factory.sockets.single
          ..addConnection(RealtimeSocketConnectionState.connected);
        await _waitUntil(() => socket.sent.isNotEmpty);

        socket
          ..addMessage(Uint8List.fromList([1, 2, 3]))
          ..addMessage('{not-json')
          ..addMessage(jsonEncode({'type': 'custom', 'value': 7}));

        expect(
          await client.webSocketMessages.first,
          containsPair('value', 7),
        );
      },
    );

    test(
      'pong deadline reconstructs rather than reusing a closed socket',
      () async {
        final factory = _FakeRealtimeSocketFactory();
        final client = _TestRealtimeClient(
          factory,
          wsPingInterval: const Duration(milliseconds: 2),
          realtimePongTimeout: const Duration(milliseconds: 5),
        );
        addTearDown(client.close);
        await client.setAuth(
          seed: _seed,
          authTokenFetcher: (_, _) async => _credentials(_accountA),
        );
        await client.bindRealtimeAccount(_accountA);
        final first = factory.sockets.single
          ..addConnection(RealtimeSocketConnectionState.connected);
        await _settle();
        _acceptAuthentication(first);

        await _waitUntil(() => factory.sockets.length >= 2);
        expect(factory.sockets.length, greaterThanOrEqualTo(2));
        expect(first.closed, isTrue);
      },
    );
  });
}

final class _FakeRealtimeSocketFactory implements RealtimeSocketFactory {
  final sockets = <_FakeRealtimeSocket>[];

  @override
  RealtimeSocket create(Uri uri) {
    final socket = _FakeRealtimeSocket();
    sockets.add(socket);
    return socket;
  }
}

final class _FakeRealtimeSocket implements RealtimeSocket {
  final _connections =
      StreamController<RealtimeSocketConnectionState>.broadcast();
  final _messages = StreamController<Object?>.broadcast();
  final sent = <Object>[];
  bool closed = false;

  @override
  Stream<RealtimeSocketConnectionState> get connection => _connections.stream;

  @override
  Stream<Object?> get messages => _messages.stream;

  void addConnection(RealtimeSocketConnectionState state) =>
      _connections.add(state);

  void addMessage(Object? message) => _messages.add(message);

  Future<void> finishConnection() => _connections.close();

  @override
  void send(Object message) => sent.add(message);

  @override
  Future<void> close() async {
    closed = true;
  }
}

final class _TestRealtimeClient extends RemoteApiClientBase
    with RemoteApiClientWs {
  _TestRealtimeClient(
    this.realtimeSocketFactory, {
    this.wsPingInterval = const Duration(hours: 1),
    this.realtimePongTimeout = const Duration(hours: 2),
  }) : super(
         userAgent: 'test',
         apiEndpointUrl: 'https://example.test/api/v1/graphql',
         apiEndpointUrlV2: 'https://example.test/api/v2/graphql',
         requestTimeout: const Duration(seconds: 1),
         authJwtExpiresIn: const Duration(minutes: 1),
       );

  @override
  final RealtimeSocketFactory realtimeSocketFactory;

  @override
  final Duration wsPingInterval;

  @override
  final Duration realtimePongTimeout;

  @override
  Duration get realtimeAuthAcknowledgementTimeout =>
      const Duration(milliseconds: 50);

  @override
  Duration get realtimeRetryBaseDelay => const Duration(milliseconds: 1);

  @override
  Duration get realtimeRetryMaxDelay => const Duration(milliseconds: 1);

  @override
  int get realtimeRetryJitterMilliseconds => 0;

  @override
  String get wsEndpointUrl => 'https://example.test/api/v2/ws';

  @override
  Stream<OperationResponse<TData, TVars>> request<TData, TVars>(
    OperationRequest<TData, TVars> request, [
    Stream<OperationResponse<TData, TVars>> Function(
      OperationRequest<TData, TVars>,
    )?
    forward,
  ]) => const Stream.empty();
}
