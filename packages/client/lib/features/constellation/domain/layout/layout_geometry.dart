/// Pure-Dart geometry carried by the layout domain. UI adapters convert to
/// `Offset`/`Size`/`Rect` at call sites.
library;

/// A point in scene coordinates.
typedef LPoint = ({double x, double y});

/// A width/height extent.
typedef LSize = ({double w, double h});

/// An axis-aligned rectangle given by its edges.
typedef LRect = ({double left, double top, double right, double bottom});

/// Midpoint of a [size] anchored at the origin.
LPoint lSizeCenter(LSize size) => (x: size.w / 2, y: size.h / 2);

/// Midpoint of [rect].
LPoint lRectCenter(LRect rect) => (
  x: (rect.left + rect.right) / 2,
  y: (rect.top + rect.bottom) / 2,
);

/// Width and height spanned by [rect].
LSize lRectSize(LRect rect) => (
  w: rect.right - rect.left,
  h: rect.bottom - rect.top,
);
