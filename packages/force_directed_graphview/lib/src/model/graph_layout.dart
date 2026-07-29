import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

/// Builder for the graph layout. Used to manipulate a mutable graph structure
/// and the build an immutable [GraphLayout] instance.
class GraphLayoutBuilder {
  /// { @nodoc }
  GraphLayoutBuilder({
    required Set<NodeBase> nodes,
  })  : nodes = Set.of(nodes),
        _positions = {};

  /// { @nodoc }
  GraphLayoutBuilder.fromLayout(GraphLayout layout)
      : nodes = layout._nodePositions.keys.toSet(),
        _positions = Map.of(layout._nodePositions);

  /// { @nodoc }
  final Set<NodeBase> nodes;

  final Map<NodeBase, Offset> _positions;

  /// Returns the position of the node.
  Offset getNodePosition(NodeBase node) => _positions[node]!;

  /// Sets the position of the node.
  void setNodePosition(NodeBase node, Offset position) =>
      _positions[node] = position;

  /// Removes the node and its position from the layout.
  void removeNode(NodeBase node) {
    nodes.remove(node);
    _positions.remove(node);
  }

  /// Adds the node to the layout
  void addNode(NodeBase node) {
    nodes.add(node);
  }

  /// Moves the node by the given delta.
  void translateNode(NodeBase node, Offset delta) {
    _positions[node] = _positions[node]! + delta;
  }

  /// Builds the [GraphLayout] instance.
  GraphLayout build() {
    if (nodes.length != _positions.length) {
      throw StateError('Not all nodes have position');
    }

    return GraphLayout._(
      Map.unmodifiable(_positions),
    );
  }
}

/// Layout of the graph. Contains the positions of all nodes.
@immutable
class GraphLayout {
  const GraphLayout._(this._nodePositions);

  /// { @nodoc }
  const GraphLayout.empty() : _nodePositions = const {};

  final Map<NodeBase, Offset> _nodePositions;

  /// Returns a node position in layout
  Offset getPosition(NodeBase node) => getPositionOrNull(node)!;

  /// Returns a node position in layout if the position exists,
  /// returns null otherwise
  Offset? getPositionOrNull(NodeBase node) => _nodePositions[node];

  /// Checks if position for node exists in the layout
  bool hasPosition(NodeBase node) => _nodePositions.containsKey(node);

  /// Interpolates between two layouts.
  ///
  /// The key set of the result is the key set of [b] — nodes that exist only in
  /// [a] have been removed from the graph and must not be rendered. A node that
  /// exists only in [b] starts from [spawn] (when provided) so that a freshly
  /// expanded node visually travels out of the node it was expanded from,
  /// instead of appearing at its final position.
  static GraphLayout lerp(
    GraphLayout a,
    GraphLayout b,
    double t, {
    Offset? Function(NodeBase node)? spawn,
  }) {
    final positions = <NodeBase, Offset>{};
    for (final entry in b._nodePositions.entries) {
      final from =
          a._nodePositions[entry.key] ?? spawn?.call(entry.key) ?? entry.value;
      positions[entry.key] = Offset.lerp(from, entry.value, t)!;
    }
    return GraphLayout._(Map.unmodifiable(positions));
  }
}
