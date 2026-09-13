import 'package:meta/meta.dart';

/// Default graph node payload used by package tests and examples.
@immutable
final class Node<T> {
  /// { @nodoc }
  const Node({
    required this.data,
    required this.size,
    this.pinned = false,
  });

  /// The data associated with this node.
  final T data;

  /// Layout bounding square edge length.
  final double size;

  /// When true, force-directed layout must not move this node.
  final bool pinned;

  @override
  int get hashCode => Object.hash(data, size, pinned);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Node<T> &&
          runtimeType == other.runtimeType &&
          data == other.data &&
          size == other.size &&
          pinned == other.pinned;

  /// { @nodoc }
  Node<T> copyWith({
    double? size,
    bool? pinned,
  }) {
    return Node<T>(
      data: data,
      size: size ?? this.size,
      pinned: pinned ?? this.pinned,
    );
  }
}
