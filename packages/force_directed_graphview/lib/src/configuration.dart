import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';

/// Resolves a stable node id for scene topology and layout.
typedef GraphNodeIdResolver<N> = GraphNodeId Function(N node);

/// Resolves a stable edge id for scene topology and layout.
typedef GraphEdgeIdResolver<E> = GraphEdgeId Function(E edge);

/// Called when a node drag is captured.
typedef NodeDragStartCallback<N> = void Function(
  N node,
  Offset scenePosition,
);

/// Called while a captured node moves.
typedef NodeDragUpdateCallback<N> = void Function(
  N node,
  Offset scenePosition,
);

/// Called when a captured node drag ends with all pointers released.
typedef NodeDragEndCallback<N> = void Function(
  N node,
  Offset scenePosition,
);

/// Called when a node drag is cancelled without a successful drop write.
typedef NodeDragCancelCallback<N> = void Function(N node);

/// Called when a pointer releases over a node without starting a drag.
typedef NodeTapCallback<N> = void Function(N node);

/// Returns whether [node] may be dragged when node-drag hooks are enabled.
typedef CanDragNodePredicate<N> = bool Function(N node);

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
    this.onNodeTap,
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
  final SceneLayoutAlgorithm layoutAlgorithm;

  /// Optional predicate for draggable nodes. Defaults to `node.size > 0`.
  final CanDragNodePredicate<dynamic>? canDragNodePredicate;

  /// Optional node-drag lifecycle hooks. When all are null the graph keeps the
  /// stock [InteractiveViewer] behaviour.
  final NodeDragStartCallback<dynamic>? onNodeDragStart;

  /// { @nodoc }
  final NodeDragUpdateCallback<dynamic>? onNodeDragUpdate;

  /// { @nodoc }
  final NodeDragEndCallback<dynamic>? onNodeDragEnd;

  /// { @nodoc }
  final NodeDragCancelCallback<dynamic>? onNodeDragCancel;

  /// Optional short-press selection hook using scene hit order.
  final NodeTapCallback<dynamic>? onNodeTap;

  /// Optional shared paint/hit order. Later entries paint and hit-test on top.
  final List<GraphNodeId>? nodePaintOrder;

  /// Whether node-drag hooks are active.
  bool get nodeDragEnabled =>
      onNodeDragStart != null ||
      onNodeDragUpdate != null ||
      onNodeDragEnd != null ||
      onNodeDragCancel != null;

  /// Whether the node pointer layer is active.
  bool get nodePointerLayerEnabled => nodeDragEnabled || onNodeTap != null;

  /// Returns whether [node] may be dragged.
  bool isNodeDraggable(dynamic node) =>
      (canDragNodePredicate ?? _defaultCanDragNode)(node);

  static bool _defaultCanDragNode(dynamic node) {
    if (node is NodeBase) {
      return node.size > 0;
    }
    return true;
  }
}
