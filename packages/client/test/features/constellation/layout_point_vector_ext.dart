import 'dart:math' as math;

import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

/// Offset-style vector reads over the domain [LPoint] record, so layout tests
/// keep asserting in the vocabulary they were written in.
extension LPointVector on LPoint {
  double get dx => x;

  double get dy => y;

  double get distance => math.sqrt(x * x + y * y);

  LPoint operator -(LPoint other) => (x: x - other.x, y: y - other.y);
}
