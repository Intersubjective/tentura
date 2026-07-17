/// Platform-neutral evidence collected for one visible attention receipt.
final class AttentionVisibilityEvidence {
  const AttentionVisibilityEvidence({
    required this.visibleFraction,
    required this.visibleFor,
    required this.appIsFocused,
    required this.routeIsCurrent,
  });

  final double visibleFraction;
  final Duration visibleFor;
  final bool appIsFocused;
  final bool routeIsCurrent;
}

/// Pure dwell policy; platform adapters provide visibility and focus evidence.
final class SeenAckCase {
  const SeenAckCase({
    this.minimumVisibleFraction = 0.6,
    this.minimumDwell = const Duration(milliseconds: 800),
  });

  final double minimumVisibleFraction;
  final Duration minimumDwell;

  bool shouldAcknowledge(AttentionVisibilityEvidence evidence) =>
      evidence.appIsFocused &&
      evidence.routeIsCurrent &&
      evidence.visibleFraction >= minimumVisibleFraction &&
      evidence.visibleFor >= minimumDwell;
}
