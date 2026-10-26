import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/util/extensions.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';
import 'package:force_directed_graphview/src/widget/node_drag_gesture.dart';
import 'package:vector_math/vector_math_64.dart';

part 'controller.dart';

/// A builder that should be used to wrap a [child] with something.
typedef ChildBuilder = Widget Function(
  BuildContext context,
  Widget child,
);

/// A widget that displays a graph.
class GraphView<N, E> extends StatefulWidget {
  /// { @nodoc }
  const GraphView({
    required this.nodeBuilder,
    required this.controller,
    required this.canvasSize,
    required this.layoutAlgorithm,
    this.lazyBuilding = const LazyBuilding.none(),
    this.edgePainter = const LineEdgePainter(),
    this.labelBuilder,
    this.canvasBackgroundBuilder,
    this.builder,
    this.minScale = 0.5,
    this.maxScale = 2,
    this.layoutTransitionDuration = Duration.zero,
    this.layoutTransitionCurve = Curves.easeOutCubic,
    this.layoutTransitionStages = const {},
    this.canDragNode,
    this.onNodeDragStart,
    this.onNodeDragUpdate,
    this.onNodeDragEnd,
    this.onNodeDragCancel,
    this.transformNodeDragPosition,
    this.onNodeTap,
    this.onCanvasTap,
    this.onCanvasSecondaryTap,
    this.onCanvasLongPress,
    this.nodeTapHitTester,
    this.nodePaintOrder,
    super.key,
  });

  /// The builder that builds the visual representation of the node.
  final NodeViewBuilder<N> nodeBuilder;

  /// The painter that paints the edge.
  final EdgePainter<N, E> edgePainter;

  /// The builder that builds the label of the node.
  final LabelBuilder<N>? labelBuilder;

  /// The builder that builds the background of the graph.
  /// If null, the background will be transparent.
  final WidgetBuilder? canvasBackgroundBuilder;

  /// The controller that controls the graph.
  final GraphController<N, E> controller;

  /// The layout algorithm that is used to layout the graph.
  final SceneLayoutAlgorithm layoutAlgorithm;

  /// The size of the graph canvas. May exceed the size of the screen.
  final GraphCanvasSize canvasSize;

  /// The strategy that is used to lazily render the graph.
  final LazyBuilding lazyBuilding;

  /// Allows to add additional widgets right above the canvas,
  /// but below the [InteractiveViewer]. Similar to [MaterialApp.builder].
  final ChildBuilder? builder;

  /// The minimum scale of the [InteractiveViewer] that wraps the graph.
  final double minScale;

  /// The maximum scale of the [InteractiveViewer] that wraps the graph.
  final double maxScale;

  /// How long the graph takes to move from the previous layout to a newly
  /// computed one. [Duration.zero] (the default) applies layouts instantly,
  /// which reproduces the pre-transition behaviour.
  ///
  /// Only meaningful together with a layout algorithm that emits its **final**
  /// layout once (e.g.
  /// `FruchtermanReingoldSceneLayoutAlgorithm(showIterations: false)`).
  /// An algorithm that streams intermediate iterations restarts the transition
  /// on every emission and will look wrong.
  final Duration layoutTransitionDuration;

  /// Easing used for [layoutTransitionDuration].
  final Curve layoutTransitionCurve;

  /// Per-node timing within a layout transition. Nodes sharing a stage move
  /// together, so a bulk move runs as a few staged groups instead of one tween
  /// per node. Nodes without an entry use the whole [layoutTransitionDuration].
  final Map<GraphNodeId, LayoutTransitionStage> layoutTransitionStages;

  /// Optional predicate for draggable nodes when node-drag hooks are enabled.
  final CanDragNodePredicate<N>? canDragNode;

  /// Optional node-drag lifecycle hooks. When all are null the graph keeps the
  /// stock [InteractiveViewer] behaviour.
  final NodeDragStartCallback<N>? onNodeDragStart;

  /// { @nodoc }
  final NodeDragUpdateCallback<N>? onNodeDragUpdate;

  /// { @nodoc }
  final NodeDragEndCallback<N>? onNodeDragEnd;

  /// { @nodoc }
  final NodeDragCancelCallback<N>? onNodeDragCancel;

  /// Optional clamp/transform of the dragged node centre during pointer move.
  final NodeDragPositionTransform<N>? transformNodeDragPosition;

  /// Optional short-press hook using scene paint/hit order (not widget z-order).
  final NodeTapCallback<N>? onNodeTap;

  /// Called for a primary short press that hits no node, in scene coordinates.
  final void Function(Offset scenePosition)? onCanvasTap;

  /// Called for a secondary short press on empty canvas, in scene coordinates.
  final void Function(Offset scenePosition)? onCanvasSecondaryTap;

  /// Called for a primary long press that hits no node, in scene coordinates.
  final void Function(Offset scenePosition)? onCanvasLongPress;

  /// Optional tap target resolver; defaults to the body hit-test result.
  final NodeTapHitTester? nodeTapHitTester;

  /// Optional shared paint/hit order. Later entries paint and hit-test on top.
  final List<GraphNodeId>? nodePaintOrder;

  @override
  State<GraphView<N, E>> createState() => _GraphViewState<N, E>();
}

class _GraphViewState<N, E> extends State<GraphView<N, E>>
    with TickerProviderStateMixin {
  final _transformationController = TransformationController();

  @override
  void initState() {
    super.initState();
    _initController();
  }

  @override
  void didUpdateWidget(covariant GraphView<N, E> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controller != oldWidget.controller) {
      oldWidget.controller._detachViewBinding(this);
    }
    if (widget.controller != oldWidget.controller ||
        widget.layoutAlgorithm != oldWidget.layoutAlgorithm ||
        widget.layoutAlgorithm.runtimeType !=
            oldWidget.layoutAlgorithm.runtimeType ||
        widget.canvasSize != oldWidget.canvasSize ||
        widget.lazyBuilding != oldWidget.lazyBuilding ||
        widget.layoutTransitionDuration != oldWidget.layoutTransitionDuration ||
        widget.layoutTransitionCurve != oldWidget.layoutTransitionCurve) {
      _initController();
    }
    widget.controller._transitionStages = widget.layoutTransitionStages;
  }

  void _initController() {
    if (widget.controller._viewOwner != null &&
        !identical(widget.controller._viewOwner, this)) {
      throw StateError(
        'GraphController is already attached to another GraphView',
      );
    }
    widget.controller._applyConfiguration(
      viewOwner: this,
      algorithm: widget.layoutAlgorithm,
      size: widget.canvasSize,
      lazyBuilding: widget.lazyBuilding,
      transformationController: _transformationController,
      vsync: this,
      transitionDuration: widget.layoutTransitionDuration,
      transitionCurve: widget.layoutTransitionCurve,
      transitionStages: widget.layoutTransitionStages,
      minScale: widget.minScale,
      maxScale: widget.maxScale,
    );
  }

  @override
  void deactivate() {
    widget.controller._abortViewGesturesForOwner(this);
    super.deactivate();
  }

  @override
  void dispose() {
    widget.controller._detachViewBinding(this);
    _transformationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return InheritedConfiguration(
      controller: widget.controller,
      configuration: GraphViewConfiguration(
        nodeBuilder: DefaultNodeBuilder<N>(builder: widget.nodeBuilder),
        edgePainter: widget.edgePainter,
        labelBuilder: widget.labelBuilder,
        canvasBackgroundBuilder: widget.canvasBackgroundBuilder,
        builder: widget.builder,
        canDragNodePredicate: widget.canDragNode == null
            ? null
            : (node) => widget.canDragNode!(node as N),
        onNodeDragStart: widget.onNodeDragStart == null
            ? null
            : (node, position) => widget.onNodeDragStart!(node as N, position),
        onNodeDragUpdate: widget.onNodeDragUpdate == null
            ? null
            : (node, position) => widget.onNodeDragUpdate!(node as N, position),
        onNodeDragEnd: widget.onNodeDragEnd == null
            ? null
            : (node, position) => widget.onNodeDragEnd!(node as N, position),
        onNodeDragCancel: widget.onNodeDragCancel == null
            ? null
            : (node) => widget.onNodeDragCancel!(node as N),
        transformNodeDragPosition: widget.transformNodeDragPosition == null
            ? null
            : (node, proposed) =>
                widget.transformNodeDragPosition!(node as N, proposed),
        onNodeTap: widget.onNodeTap == null
            ? null
            : (node) => widget.onNodeTap!(node as N),
        onCanvasTap: widget.onCanvasTap,
        onCanvasSecondaryTap: widget.onCanvasSecondaryTap,
        onCanvasLongPress: widget.onCanvasLongPress,
        nodeTapHitTester: widget.nodeTapHitTester,
        nodePaintOrder: widget.nodePaintOrder,
      ),
      child: _CameraGatedInteractiveViewer(
        controller: widget.controller,
        transformationController: _transformationController,
        minScale: widget.minScale,
        maxScale: widget.maxScale,
      ),
    );
  }
}

class _CameraGatedInteractiveViewer extends StatefulWidget {
  const _CameraGatedInteractiveViewer({
    required this.controller,
    required this.transformationController,
    required this.minScale,
    required this.maxScale,
  });

  final GraphController<dynamic, dynamic> controller;
  final TransformationController transformationController;
  final double minScale;
  final double maxScale;

  @override
  State<_CameraGatedInteractiveViewer> createState() =>
      _CameraGatedInteractiveViewerState();
}

class _CameraGatedInteractiveViewerState
    extends State<_CameraGatedInteractiveViewer> {
  final _viewerKey = GlobalKey();
  var _cameraGated = false;
  var _zoomGated = false;

  Offset? _globalToViewportLocal(Offset global) {
    final box = _viewerKey.currentContext?.findRenderObject();
    return box is RenderBox && box.hasSize ? box.globalToLocal(global) : null;
  }

  @override
  void initState() {
    super.initState();
    _cameraGated = widget.controller.isCameraGated;
    _zoomGated = widget.controller.isCameraZoomGated;
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(covariant _CameraGatedInteractiveViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _cameraGated = widget.controller.isCameraGated;
      _zoomGated = widget.controller.isCameraZoomGated;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final gated = widget.controller.isCameraGated;
    final zoomGated = widget.controller.isCameraZoomGated;
    if ((gated == _cameraGated && zoomGated == _zoomGated) || !mounted) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || (gated == _cameraGated && zoomGated == _zoomGated)) {
        return;
      }
      setState(() {
        _cameraGated = gated;
        _zoomGated = zoomGated;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        widget.controller
          .._globalToViewportLocal = _globalToViewportLocal
          .._onLayoutConstraintsChanged(constraints.biggest);
        return InteractiveViewer.builder(
          key: _viewerKey,
          transformationController: widget.transformationController,
          maxScale: widget.maxScale,
          minScale: widget.minScale,
          panEnabled: !_cameraGated,
          // Wheel and trackpad zoom stay live during a node drag; the drag
          // re-projects its grab point on every camera change.
          scaleEnabled: !_zoomGated,
          onInteractionStart: (_) => widget.controller._onUserCameraInput(),
          builder: (context, viewport) {
            widget.controller._updateViewport(viewport, constraints.biggest);
            return const NodeDragGesture(
              child: GraphLayoutView(),
            );
          },
        );
      },
    );
  }
}
