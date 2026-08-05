import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Publishes the latest head-refresh latency for WebDriver harnesses.
abstract final class QaAttentionLatencyProbe {
  static void publishHeadRefreshLatencyMs(int latencyMs) {
    (web.window as JSObject)['__tenturaQaHeadRefreshLatencyMs'] =
        latencyMs.toJS;
  }
}
