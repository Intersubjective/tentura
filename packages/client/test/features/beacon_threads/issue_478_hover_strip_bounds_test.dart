import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';

/// #478 review: the hover strip stays inside its bounds sideways too. On a
/// narrow window a short incoming bubble (strip pinned to its right edge)
/// pushed the strip past the left edge.
void main() {
  const bounds = Rect.fromLTWH(0, 0, 320, 600);
  const strip = Size(160, 40);

  Offset place(Rect bubble, {required bool alignLeft}) => HoverToolbarLayout(
    bubble: bubble,
    bounds: bounds,
    alignLeft: alignLeft,
    overlap: 6,
  ).getPositionForChild(bounds.size, strip);

  test('a short incoming bubble keeps the strip inside the left edge', () {
    final at = place(const Rect.fromLTWH(12, 300, 60, 36), alignLeft: false);
    expect(at.dx, bounds.left);
  });

  test('an own bubble near the right edge keeps the strip inside it', () {
    final at = place(const Rect.fromLTWH(260, 300, 50, 36), alignLeft: true);
    expect(at.dx, bounds.right - strip.width);
  });

  test('a strip with room stays pinned to the bubble edge', () {
    const bubble = Rect.fromLTWH(20, 300, 240, 36);
    expect(place(bubble, alignLeft: true).dx, bubble.left + 4);
    expect(
      place(bubble, alignLeft: false).dx,
      bubble.right - 4 - strip.width,
    );
  });

  test('a strip wider than its bounds starts at the left edge', () {
    final at = HoverToolbarLayout(
      bubble: const Rect.fromLTWH(10, 300, 60, 36),
      bounds: const Rect.fromLTWH(8, 0, 100, 600),
      alignLeft: false,
      overlap: 6,
    ).getPositionForChild(const Size(320, 600), strip);
    expect(at.dx, 8);
  });
}
