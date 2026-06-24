import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:tentura_root/consts.dart';

/// POST with Bearer (no cookies). Used for `/session/from-bearer` on all platforms.
Future<http.Response> postSessionRequest({
  required Uri uri,
  required String userAgent,
  required Duration timeout,
  String? bearerToken,
  String? authAttemptId,
}) {
  final headers = <String, String>{
    kHeaderUserAgent: userAgent,
    kHeaderAccept: 'application/json',
    if (bearerToken != null) 'Authorization': 'Bearer $bearerToken',
    if (authAttemptId != null && authAttemptId.isNotEmpty)
      kHeaderAuthAttemptId: authAttemptId,
  };
  return http.post(uri, headers: headers).timeout(timeout);
}

Future<Map<String, dynamic>> decodeJsonResponse(http.Response response) async {
  if (response.statusCode < 200 || response.statusCode >= 300) {
    throw SessionHttpException(response.statusCode);
  }
  return jsonDecode(response.body) as Map<String, dynamic>;
}

final class SessionHttpException implements Exception {
  SessionHttpException(this.statusCode);
  final int statusCode;
}
