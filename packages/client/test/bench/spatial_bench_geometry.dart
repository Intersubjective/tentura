import 'dart:math' as math;

import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

bool overlaps(LRect a, LRect b) =>
    a.left < b.right &&
    b.left < a.right &&
    a.top < b.bottom &&
    b.top < a.bottom;

LRect bounds(LRect a, LRect b) => (
  left: math.min(a.left, b.left),
  top: math.min(a.top, b.top),
  right: math.max(a.right, b.right),
  bottom: math.max(a.bottom, b.bottom),
);

double perimeter(LRect rect) =>
    2 * (rect.right - rect.left + rect.bottom - rect.top);
