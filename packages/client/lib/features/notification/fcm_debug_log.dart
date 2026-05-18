import 'package:flutter/foundation.dart';

/// Verbose FCM tracing for debug/profile builds (dev server experiments).
bool get fcmVerboseLogging => kDebugMode || kProfileMode;

void fcmLog(String message) {
  if (fcmVerboseLogging) {
    debugPrint('[FCM] $message');
  }
}

/// Short token fingerprint for logs (never log full token in production).
String fcmTokenFingerprint(String? token) {
  if (token == null || token.isEmpty) {
    return 'none';
  }
  if (token.length <= 12) {
    return '${token.length}chars';
  }
  return '${token.substring(0, 8)}…(${token.length})';
}
