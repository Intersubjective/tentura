// A real `RemoteApiService` over the real Ferry link chain; only the HTTP
// transport is faked (via `http.runWithClient`). Repository wire tests use it
// to pin the variables each operation sends, the response mapping, and the
// typed exceptions the shared error link throws for server error codes.

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/env.dart';

typedef WireSent = ({String operationName, Map<String, dynamic> variables});

/// A GraphQL error carrying a numeric server exception [code].
Map<String, dynamic> wireCodeError(int code) => {
  'message': 'error $code',
  'extensions': {'code': code.toString()},
};

/// Runs [body] against a real [RemoteApiService] whose transport answers each
/// GraphQL operation (keyed by operation name) with [responses] `data`, or
/// with [errors] when the operation is listed there. Every request is
/// recorded in [sent].
Future<void> withRemoteWire(
  Map<String, Map<String, dynamic>> responses,
  List<WireSent> sent,
  Future<void> Function(RemoteApiService remote) body, {
  Map<String, Map<String, dynamic>> errors = const {},
}) => http.runWithClient(
  () async {
    final remote = RemoteApiService(
      const Env(),
      const WebSocketClientRealtimeSocketFactory(),
    );
    try {
      await remote.setSessionAuth();
      await body(remote);
    } finally {
      await remote.close();
    }
  },
  () => MockClient((request) async {
    if (request.url.path.endsWith('/session/access-token')) {
      return http.Response(
        jsonEncode({
          'subject': 'Uviewer000001',
          'access_token': 'test-token',
          'expires_in': 3600,
        }),
        200,
        headers: {'content-type': 'application/json'},
      );
    }
    final json = jsonDecode(request.body) as Map<String, dynamic>;
    final name = json['operationName'] as String;
    sent.add((
      operationName: name,
      variables: ((json['variables'] as Map?) ?? const {})
          .cast<String, dynamic>(),
    ));
    final error = errors[name];
    return http.Response(
      jsonEncode(
        error != null
            ? {
                'data': null,
                'errors': [error],
              }
            : {'data': responses[name]},
      ),
      200,
      headers: {'content-type': 'application/json'},
    );
  }),
);
