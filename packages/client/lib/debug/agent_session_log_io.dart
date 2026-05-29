import 'dart:convert';
import 'dart:io' show File, FileMode;

import 'package:flutter/foundation.dart';

const _kAgentLogPath = '/home/vader/MY_SRC/tentura/.cursor/debug-b0129e.log';

void agentSessionLog({
  required String location,
  required String message,
  required String hypothesisId,
  Map<String, Object?> data = const {},
  String runId = 'run1',
}) {
  final payload = jsonEncode({
      'sessionId': 'b0129e',
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'location': location,
      'message': message,
      'hypothesisId': hypothesisId,
      'runId': runId,
      'data': data,
    });
  assert(() {
    debugPrint('AGENT_DBG $payload');
    return true;
  }());
  try {
    File(_kAgentLogPath).writeAsStringSync(
      '$payload\n',
      mode: FileMode.append,
      flush: true,
    );
  } on Object {
    // ignore: avoid_catches_without_on_clauses
  }
}
