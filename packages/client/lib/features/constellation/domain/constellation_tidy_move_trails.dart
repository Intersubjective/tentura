import 'layout/layout_geometry.dart';

/// Where a person was and where «Tidy up» put them.
typedef ConstellationMoveTrail = ({LPoint from, LPoint to});

/// Trails left by «Tidy up»; they fade out over [fadeDuration].
class ConstellationMoveTrails {
  const ConstellationMoveTrails(this.trails);

  static const fadeDuration = Duration(milliseconds: 1500);

  final Map<String, ConstellationMoveTrail> trails;

  /// Nodes jump at once when [reducedMotion]; trails still show and fade.
  static Duration nodeAnimationDuration({required bool reducedMotion}) =>
      reducedMotion ? Duration.zero : const Duration(milliseconds: 300);

  double opacityAt(Duration elapsed) =>
      (1 - elapsed.inMicroseconds / fadeDuration.inMicroseconds).clamp(
        0.0,
        1.0,
      );

  bool isVisibleAt(Duration elapsed) => opacityAt(elapsed) > 0;
}
