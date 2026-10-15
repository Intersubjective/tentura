import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';

// Shared stub server for tests that drive the real RemoteApiService over a
// faked HTTP edge, so they pin retry behaviour regardless of which layer
// performs the retry.

http.Response jsonResponse(Map<String, Object?> body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json'},
);

/// Same wire shape as the server's ConstellationException.toMap for the
/// admission backoff: numeric-string code 1704 plus a `retryAfterMs` hint.
http.Response retryLaterResponse(int retryAfterMs) => jsonResponse({
  'errors': [
    {
      'message': 'Constellation database busy, retry later',
      'extensions': {'code': '1704', 'retryAfterMs': retryAfterMs},
    },
  ],
});

typedef RecordedCall = ({
  String operation,
  Map<String, dynamic> vars,
  DateTime at,
});

/// Stub server that records every GraphQL call and lets [respond] decide the
/// answer given the 1-based attempt number for that operation + variables.
({MockClient client, List<RecordedCall> calls}) stubServer(
  http.Response Function(RecordedCall call, int attempt) respond,
) {
  final calls = <RecordedCall>[];
  final attempts = <String, int>{};
  final client = MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return jsonResponse({
        'subject': 'Uviewer000001',
        'access_token': 'test-token',
        'expires_in': 3600,
      });
    }
    final body = jsonDecode(request.body) as Map<String, dynamic>;
    final call = (
      operation: body['operationName']! as String,
      vars: (body['variables'] as Map<String, dynamic>?) ?? const {},
      at: DateTime.now(),
    );
    calls.add(call);
    final key = '${call.operation}:${jsonEncode(call.vars)}';
    final attempt = attempts.update(key, (n) => n + 1, ifAbsent: () => 1);
    return respond(call, attempt);
  });
  return (client: client, calls: calls);
}

Future<T> withRemote<T>(
  MockClient server,
  Future<T> Function(RemoteApiService remote) body,
) => http.runWithClient(() async {
  final remote = RemoteApiService(
    const Env(),
    const WebSocketClientRealtimeSocketFactory(),
  );
  try {
    await remote.setSessionAuth();
    return await body(remote);
  } finally {
    await remote.close();
  }
}, () => server);
