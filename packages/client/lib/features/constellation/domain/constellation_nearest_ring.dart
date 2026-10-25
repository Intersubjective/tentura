import 'dart:math' as math;

import 'constellation_consts.dart';

/// The trust ring nearest to a point, as `steps` from the viewer and its
/// scene `radius`.
typedef ConstellationNearestRing = ({int steps, double radius});

/// The ring around `centre` (the viewer) closest to `point`; a point on the
/// viewer snaps to the first ring, never to step zero.
ConstellationNearestRing constellationNearestRing({
  required ({double x, double y}) centre,
  required ({double x, double y}) point,
}) {
  final distance = math.sqrt(
    math.pow(point.x - centre.x, 2) + math.pow(point.y - centre.y, 2),
  );
  final steps = math.max(1, (distance / kConstellationRingUnitPixels).round());
  return (steps: steps, radius: steps * kConstellationRingUnitPixels);
}
