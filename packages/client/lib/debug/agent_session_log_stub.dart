import 'dart:convert';

import 'package:flutter/foundation.dart';

void agentSessionLog({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, Object?> data = const {},
  String runId = 'run1',
}) {
  assert(() {
    debugPrint(
      'AGENT_DBG ${jsonEncode({
        'sessionId': 'b0129e',
        'location': location,
        'message': message,
        'hypothesisId': hypothesisId,
        'runId': runId,
        'data': data,
      })}',
    );
    return true;
  }());
}
