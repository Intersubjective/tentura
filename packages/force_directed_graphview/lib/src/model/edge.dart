import 'package:meta/meta.dart';

/// Model that represents an edge in the graph.
@immutable
final class Edge<N, T> {
  /// { @nodoc }
  const Edge({
    required this.source,
    required this.destination,
    required this.data,
  });

  /// Start node of the edge.
  final N source;

  /// End node of the edge.
  final N destination;

  /// Value associated with this edge.
  final T data;

  @override
  int get hashCode => Object.hash(source, destination, data);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Edge<N, T> &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          destination == other.destination &&
          data == other.data;
}
