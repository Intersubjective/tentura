import 'package:shelf_plus/shelf_plus.dart';

import 'package:tentura_server/env.dart';

/// Whether [request] may use a `/_qa/*` endpoint: QA auth must be enabled
/// and the request must carry `QA_AUTH_TOKEN`, either as the `_qa_token`
/// query parameter or as an `Authorization: Bearer` header.
bool isQaRequestAllowed(Request request, Env env) {
  if (!env.isQaAuthEnabled) {
    return false;
  }
  final expected = env.qaAuthToken;
  final queryToken = request.url.queryParameters['_qa_token'];
  final authorization = request.headers['authorization'] ?? '';
  final bearerToken = authorization.toLowerCase().startsWith('bearer ')
      ? authorization.substring(7).trim()
      : null;
  // Evaluate both so the time taken does not depend on which one matched.
  final queryMatches = _constantTimeEquals(queryToken, expected);
  final bearerMatches = _constantTimeEquals(bearerToken, expected);
  return queryMatches || bearerMatches;
}

bool _constantTimeEquals(String? candidate, String expected) {
  if (candidate == null || candidate.length != expected.length) {
    return false;
  }
  var diff = 0;
  for (var i = 0; i < expected.length; i++) {
    diff |= candidate.codeUnitAt(i) ^ expected.codeUnitAt(i);
  }
  return diff == 0;
}
