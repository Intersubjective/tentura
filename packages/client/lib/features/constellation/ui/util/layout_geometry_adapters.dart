import 'dart:ui' show Offset, Size;

import '../../domain/layout/layout_geometry.dart';

/// UI-side bridges between `dart:ui` geometry and the pure layout-domain
/// records.
extension OffsetLayoutPoint on Offset {
  LPoint get lPoint => (x: dx, y: dy);
}

extension LayoutPointOffset on LPoint {
  Offset get offset => Offset(x, y);
}

extension SizeLayoutSize on Size {
  LSize get lSize => (w: width, h: height);
}

extension OffsetMapLayoutPoints on Map<String, Offset> {
  Map<String, LPoint> get lPoints => {
    for (final entry in entries) entry.key: entry.value.lPoint,
  };
}
