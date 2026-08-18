import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

/// Bubble shape implementation with 16px/6px per-corner radii capability
/// mirroring clean-room chat specifications while keeping [Material] ink clip.
class RoomMessageBubbleShape extends ShapeBorder {
  const RoomMessageBubbleShape({
    this.topLeft = 16.0,
    this.topRight = 16.0,
    this.bottomLeft = 16.0,
    this.bottomRight = 16.0,
    this.side = BorderSide.none,
  });

  final double topLeft;
  final double topRight;
  final double bottomLeft;
  final double bottomRight;
  final BorderSide side;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(side.width);

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return _getPath(rect.deflate(side.width), textDirection);
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return _getPath(rect, textDirection);
  }

  Path _getPath(Rect rect, TextDirection? textDirection) {
    final path = Path();

    var tl = topLeft;
    var tr = topRight;
    var bl = bottomLeft;
    var br = bottomRight;

    if (textDirection == TextDirection.rtl) {
      final swapTop = tl;
      tl = tr;
      tr = swapTop;

      final swapBottom = bl;
      bl = br;
      br = swapBottom;
    }

    path.addRRect(
      RRect.fromRectAndCorners(
        rect,
        topLeft: Radius.circular(tl),
        topRight: Radius.circular(tr),
        bottomLeft: Radius.circular(bl),
        bottomRight: Radius.circular(br),
      ),
    );

    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none) {
      return;
    }

    final paint = side.toPaint();
    // Inset by half the border width so it paints within the bounds
    final innerRect = rect.deflate(side.width / 2.0);
    final path = _getPath(innerRect, textDirection);
    canvas.drawPath(path, paint);
  }

  @override
  ShapeBorder scale(double t) {
    return RoomMessageBubbleShape(
      topLeft: topLeft * t,
      topRight: topRight * t,
      bottomLeft: bottomLeft * t,
      bottomRight: bottomRight * t,
      side: side.scale(t),
    );
  }

  @override
  ShapeBorder? lerpFrom(ShapeBorder? a, double t) {
    if (a is RoomMessageBubbleShape) {
      return RoomMessageBubbleShape(
        topLeft: lerpDouble(a.topLeft, topLeft, t) ?? topLeft,
        topRight: lerpDouble(a.topRight, topRight, t) ?? topRight,
        bottomLeft: lerpDouble(a.bottomLeft, bottomLeft, t) ?? bottomLeft,
        bottomRight: lerpDouble(a.bottomRight, bottomRight, t) ?? bottomRight,
        side: BorderSide.lerp(a.side, side, t),
      );
    }
    return super.lerpFrom(a, t);
  }

  @override
  ShapeBorder? lerpTo(ShapeBorder? b, double t) {
    if (b is RoomMessageBubbleShape) {
      return RoomMessageBubbleShape(
        topLeft: lerpDouble(topLeft, b.topLeft, t) ?? b.topLeft,
        topRight: lerpDouble(topRight, b.topRight, t) ?? b.topRight,
        bottomLeft: lerpDouble(bottomLeft, b.bottomLeft, t) ?? b.bottomLeft,
        bottomRight: lerpDouble(bottomRight, b.bottomRight, t) ?? b.bottomRight,
        side: BorderSide.lerp(side, b.side, t),
      );
    }
    return super.lerpTo(b, t);
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other.runtimeType != runtimeType) return false;
    return other is RoomMessageBubbleShape &&
        other.topLeft == topLeft &&
        other.topRight == topRight &&
        other.bottomLeft == bottomLeft &&
        other.bottomRight == bottomRight &&
        other.side == side;
  }

  @override
  int get hashCode =>
      Object.hash(topLeft, topRight, bottomLeft, bottomRight, side);
}
