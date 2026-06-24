import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'package:tentura_root/consts.dart';

export 'session_fetch_stub.dart'
    show SessionHttpException, decodeJsonResponse;

/// Credentialed POST for cookie session endpoints (web only).
Future<http.Response> postSessionRequest({
  required Uri uri,
  required String userAgent,
  required Duration timeout,
  String? bearerToken,
  String? authAttemptId,
}) async {
  final headers = web.Headers();
  headers.set(kHeaderUserAgent, userAgent);
  headers.set(kHeaderAccept, 'application/json');
  if (bearerToken != null) {
    headers.set('Authorization', 'Bearer $bearerToken');
  }
  if (authAttemptId != null && authAttemptId.isNotEmpty) {
    headers.set(kHeaderAuthAttemptId, authAttemptId);
  }
  final init = web.RequestInit(
    method: 'POST',
    credentials: 'include',
    headers: headers,
  );
  final response = await web.window
      .fetch(uri.toString().toJS, init)
      .toDart
      .timeout(timeout);
  final body = (await response.text().toDart).toDart;
  return http.Response(body, response.status);
}
