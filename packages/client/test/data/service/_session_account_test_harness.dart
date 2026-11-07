// Shared fake-server + realtime-socket harness for the #1044 session-account
// binding tests. The wire-level tests (data/service) and the cubit-level notice
// test (features/auth) both drive the same cookie-swap surface, so the doubles
// live here once.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/auth/domain/exception.dart'
    show AuthException, AuthSessionLostException, SessionAuthRejectedException;

/// A mutable view of the shared HttpOnly session cookie: another tab can swap
/// the user behind it at any time.
class FakeSessionCookie {
  String subject;
  String token;
  int expiresIn;

  FakeSessionCookie({
    required this.subject,
    required this.token,
    this.expiresIn = 0,
  });
}

/// MockClient that mints access tokens from [cookie] on
/// `POST /api/v2/session/access-token` and records every request seen.
/// `expiresIn` defaults to 0 so each [RemoteApiClientBase.getAuthToken] after
/// the first re-fetches from the cookie (the leak surface under test).
MockClient fakeSessionServer(
  FakeSessionCookie cookie, {
  List<http.Request>? seen,
  http.Client? graphQlServer,
}) {
  final recorded = seen ?? <http.Request>[];
  return MockClient((request) async {
    recorded.add(request);
    if (request.url.path == '/api/v2/session/access-token') {
      return http.Response(
        jsonEncode({
          'subject': cookie.subject,
          'access_token': cookie.token,
          'expires_in': cookie.expiresIn,
        }),
        200,
      );
    }
    if (request.url.path.endsWith('/graphql') && graphQlServer != null) {
      // MockClient has already finalized its input. Forward a fresh wire
      // request to the existing round-trip harness, preserving its payload.
      final forwarded = http.Request(request.method, request.url)
        ..headers.addAll(request.headers)
        ..bodyBytes = request.bodyBytes;
      return http.Response.fromStream(await graphQlServer.send(forwarded));
    }
    return http.Response('{}', 200);
  });
}

/// Realtime socket factory whose sockets are kept and can be driven by a test.
final class FakeRealtimeSocketFactory implements RealtimeSocketFactory {
  final sockets = <FakeRealtimeSocket>[];

  @override
  RealtimeSocket create(Uri uri) {
    final socket = FakeRealtimeSocket();
    sockets.add(socket);
    return socket;
  }
}

final class FakeRealtimeSocket implements RealtimeSocket {
  final _connections =
      StreamController<RealtimeSocketConnectionState>.broadcast();
  final _messages = StreamController<Object?>.broadcast();
  final sent = <Object>[];

  @override
  Stream<RealtimeSocketConnectionState> get connection => _connections.stream;

  @override
  Stream<Object?> get messages => _messages.stream;

  void addConnection(RealtimeSocketConnectionState state) =>
      _connections.add(state);

  void addMessage(Object? message) => _messages.add(message);

  @override
  void send(Object message) => sent.add(message);

  @override
  Future<void> close() async {
    await _connections.close();
    await _messages.close();
  }
}

/// A no-op socket for tests that only exercise the HTTP refresh path.
final class NoopRealtimeSocketFactory implements RealtimeSocketFactory {
  @override
  RealtimeSocket create(Uri uri) => NoopRealtimeSocket();
}

final class NoopRealtimeSocket implements RealtimeSocket {
  final _connections =
      StreamController<RealtimeSocketConnectionState>.broadcast();
  final _messages = StreamController<Object?>.broadcast();

  @override
  Stream<RealtimeSocketConnectionState> get connection => _connections.stream;

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  void send(Object message) {}

  @override
  Future<void> close() async {
    await _connections.close();
    await _messages.close();
  }
}

/// The production HTTP/Ferry/auth/realtime client; only its external socket and
/// HTTP peers are faked. In particular, GraphQL requests are never stubbed out.
RemoteApiService testRealtimeClient({
  RealtimeSocketFactory? socketFactory,
}) => RemoteApiService(
  const Env(),
  socketFactory ?? NoopRealtimeSocketFactory(),
);

/// Pin the dedicated exception from the transport contract. Comparing its
/// concrete type name lets these RED tests compile before that class exists;
/// requiring the sealed production AuthException family also rules out a
/// test-defined/ad-hoc Localizable with matching copy.
Matcher get isSessionAccountChangedNotice {
  return allOf([
    isA<AuthException>().having(
      (error) => error.runtimeType.toString(),
      'dedicated auth exception type',
      'AuthSessionAccountChangedException',
    ),
    predicate<AuthException>(
      (l) => l.toEn.isNotEmpty && l.toRu.isNotEmpty,
      'has non-empty EN and RU copy',
    ),
    predicate<AuthException>(
      (l) => l.toEn != l.toRu,
      'EN and RU copy differ',
    ),
    predicate<AuthException>(
      (l) => l.toEn != const AuthSessionLostException().toEn,
      'EN copy is not the session-lost notice',
    ),
    predicate<AuthException>(
      (l) => l.toEn != const SessionAuthRejectedException().toEn,
      'EN copy is not the session-rejected notice',
    ),
  ]);
}

/// Bounded wait for [condition] to become true; fails with [message] instead of
/// hanging the runner when the expected frame never arrives.
Future<void> waitUntil(
  String message,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
  Duration step = const Duration(milliseconds: 5),
}) async {
  final deadline = DateTime.timestamp().add(timeout);
  while (DateTime.timestamp().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(step);
  }
  fail(message);
}
