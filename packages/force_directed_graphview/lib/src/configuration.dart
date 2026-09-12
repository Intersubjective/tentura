import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

/// Resolves a stable node id for scene topology and layout.
typedef GraphNodeIdResolver<N extends NodeBase> = GraphNodeId Function(N node);

/// Resolves a stable edge id for scene topology and layout.
typedef GraphEdgeIdResolver<E extends EdgeBase> = GraphEdgeId Function(E edge);

/// Called when a node drag is captured.
typedef NodeDragStartCallback<N extends NodeBase> = void Function(
  N node,
  Offset scenePosition,
);

/// Called while a captured node moves.
typedef NodeDragUpdateCallback<N extends NodeBase> = void Function(
  N node,
  Offset scenePosition,
);

/// Called when a captured node drag ends with all pointers released.
typedef NodeDragEndCallback<N extends NodeBase> = void Function(
  N node,
  Offset scenePosition,
);

/// Called when a node drag is cancelled without a successful drop write.
typedef NodeDragCancelCallback<N extends NodeBase> = void Function(N node);

/// Returns whether [node] may be dragged when node-drag hooks are enabled.
typedef CanDragNodePredicate<N extends NodeBase> = bool Function(N node);

/// Configuration for the graph view.
/// Used as a convenient way to pass multiple parameters
/// to the internal widgets.
@immutable
class GraphViewConfiguration {
  /// { @nodoc }
  const GraphViewConfiguration({
    required this.nodeBuilder,
    required this.edgePainter,
    required this.labelBuilder,
    required this.layoutAlgorithm,
    required this.canvasBackgroundBuilder,
    required this.builder,
    this.canDragNodePredicate,
    this.onNodeDragStart,
    this.onNodeDragUpdate,
    this.onNodeDragEnd,
    this.onNodeDragCancel,
    this.nodePaintOrder,
  });

  /// { @nodoc }
  final NodeBuilder nodeBuilder;

  /// { @nodoc }
  final EdgePainter edgePainter;

  /// { @nodoc }
  final LabelBuilder? labelBuilder;

  /// { @nodoc }
  final WidgetBuilder? canvasBackgroundBuilder;

  /// { @nodoc }
  final ChildBuilder? builder;

  /// { @nodoc }
  final GraphLayoutAlgorithm layoutAlgorithm;

  /// Optional predicate for draggable nodes. Defaults to `node.size > 0`.
  final CanDragNodePredicate<NodeBase>? canDragNodePredicate;

  /// Optional node-drag lifecycle hooks. When all are null the graph keeps the
  /// stock [InteractiveViewer] behaviour.
  final NodeDragStartCallback<NodeBase>? onNodeDragStart;

  /// { @nodoc }
  final NodeDragUpdateCallback<NodeBase>? onNodeDragUpdate;

  /// { @nodoc }
  final NodeDragEndCallback<NodeBase>? onNodeDragEnd;

  /// { @nodoc }
  final NodeDragCancelCallback<NodeBase>? onNodeDragCancel;

  /// Optional shared paint/hit order. Later entries paint and hit-test on top.
  final List<NodeBase>? nodePaintOrder;

  /// Whether node-drag hooks are active.
  bool get nodeDragEnabled =>
      onNodeDragStart != null ||
      onNodeDragUpdate != null ||
      onNodeDragEnd != null ||
      onNodeDragCancel != null;

  /// Returns whether [node] may be dragged.
  bool isNodeDraggable(NodeBase node) =>
      (canDragNodePredicate ?? _defaultCanDragNode)(node);

  static bool _defaultCanDragNode(NodeBase node) => node.size > 0;
}
