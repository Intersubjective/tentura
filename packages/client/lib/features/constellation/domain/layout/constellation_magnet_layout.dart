import 'layout_geometry.dart';

/// A soft layout bias, not a pin: multiple matching magnets contribute equally.
LPoint attractToTagMagnets(LPoint origin, Iterable<LPoint> magnets) {
  var x = 0.0;
  var y = 0.0;
  var count = 0;
  for (final magnet in magnets) {
    x += magnet.x;
    y += magnet.y;
    count++;
  }
  if (count == 0) return origin;
  const strength = 0.8;
  return (
    x: origin.x + (x / count - origin.x) * strength,
    y: origin.y + (y / count - origin.y) * strength,
  );
}
