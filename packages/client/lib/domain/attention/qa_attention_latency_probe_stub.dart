/// QA-only bridge for integration harnesses; no-op off web.
abstract final class QaAttentionLatencyProbe {
  static void publishHeadRefreshLatencyMs(int latencyMs) {}
}
