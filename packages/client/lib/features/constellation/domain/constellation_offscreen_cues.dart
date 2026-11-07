/// Edge of the Field safe viewport where off-screen nodes cluster.
enum ConstellationOffscreenSide {
  left,
  right,
  above,
  below,
}

/// Counts and nearest targets per side for off-screen Field cues.
final class ConstellationOffscreenCueSnapshot {
  const ConstellationOffscreenCueSnapshot({
    required this.left,
    required this.right,
    required this.above,
    required this.below,
    required this.nearestBySide,
  });

  const ConstellationOffscreenCueSnapshot.empty()
    : left = 0,
      right = 0,
      above = 0,
      below = 0,
      nearestBySide = const {};

  final int left;
  final int right;
  final int above;
  final int below;
  /// Graph scene node ids (e.g. `fp:<personId>`), keyed by cue side.
  final Map<ConstellationOffscreenSide, String> nearestBySide;

  int countFor(ConstellationOffscreenSide side) => switch (side) {
    ConstellationOffscreenSide.left => left,
    ConstellationOffscreenSide.right => right,
    ConstellationOffscreenSide.above => above,
    ConstellationOffscreenSide.below => below,
  };

  bool get hasAny => left + right + above + below > 0;
}
