import 'dart:math' as math;

import 'package:meta/meta.dart';

/// Rejects non-finite scalars used in scene geometry.
void assertFiniteSceneScalar(double value, String name) {
  if (!value.isFinite) {
    throw ArgumentError.value(value, name, 'must be finite');
  }
}

/// Rejects negative non-finite width/height for node or canvas bounds.
void assertNonNegativeFiniteSceneScalar(double value, String name) {
  assertFiniteSceneScalar(value, name);
  if (value < 0) {
    throw ArgumentError.value(value, name, 'must be non-negative');
  }
}

/// A finite point in scene space (pure Dart; not a Flutter offset).
@immutable
final class ScenePoint {
  const ScenePoint._(this.x, this.y);

  /// Creates a point with finite coordinates.
  factory ScenePoint({required double x, required double y}) {
    assertFiniteSceneScalar(x, 'x');
    assertFiniteSceneScalar(y, 'y');
    return ScenePoint._(x, y);
  }

  final double x;
  final double y;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScenePoint && x == other.x && y == other.y;

  @override
  int get hashCode => Object.hash(x, y);

  @override
  String toString() => 'ScenePoint($x, $y)';
}

/// Width and height in scene space; zero is allowed.
@immutable
final class SceneSize {
  const SceneSize._(this.width, this.height);

  /// Creates a size with finite, non-negative width and height.
  factory SceneSize({required double width, required double height}) {
    assertNonNegativeFiniteSceneScalar(width, 'width');
    assertNonNegativeFiniteSceneScalar(height, 'height');
    return SceneSize._(width, height);
  }

  final double width;
  final double height;

  double get shortestSide => math.min(width, height);

  double get longestSide => math.max(width, height);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SceneSize && width == other.width && height == other.height;

  @override
  int get hashCode => Object.hash(width, height);

  @override
  String toString() => 'SceneSize($width, $height)';
}
