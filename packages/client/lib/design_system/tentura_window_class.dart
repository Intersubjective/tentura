import 'package:flutter/material.dart';

/// Width-based layout class. Typography stays fixed; only `TenturaTokens` density
/// fields change per class.
enum WindowClass {
  compact,
  regular,
  expanded,
}

/// [WindowClass.regular] is **600 ≤ width < 840** (see `docs/tentura-design-system.md`).
WindowClass windowClassForWidth(double width) {
  if (width < 600) return WindowClass.compact;
  if (width < 840) return WindowClass.regular;
  return WindowClass.expanded;
}

extension TenturaWindowClassX on BuildContext {
  WindowClass get windowClass =>
      windowClassForWidth(MediaQuery.sizeOf(this).width);
}
