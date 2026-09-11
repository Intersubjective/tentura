part of 'graph_view.dart';

/// Controller to manipulate the [GraphView].
class GraphController<N extends NodeBase, E extends EdgeBase<N>>
    with ChangeNotifier {
  final _nodes = <N>{};
  final _edges = <E>{};

  GraphLayout? _layout;

  // Region of canvas that is building its nodes now
  Rect? _effectiveViewport;
  Rect? _actualViewport;
  Size? _viewportPixelSize;
  GraphLayoutAlgorithm? _currentAlgorithm;
  LazyBuilding? _lazyBuilding;
  TransformationController? _transformationController;
  GraphCanvasSize? _size;

  Size? _currentSize;
  var _centered = false;
  var _relayoutGeneration = 0;
  var _relayoutInFlight = false;
  var _relayoutInvocationCount = 0;
  final _presentationPositions = <N, Offset>{};
  var _cameraGated = false;
  Ticker? _ticker;
  GraphLayout? _transitionFrom;
  GraphLayout? _transitionTarget;
  Duration _transitionDuration = Duration.zero;
  Curve _transitionCurve = Curves.easeOutCubic;
  double _minScale = 0.5;
  double _maxScale = 2;

  /// Resolves where a node that is new to the layout should start its transition.
  /// Set by the owner (e.g. "the node the user just expanded"). When the field
  /// is null, or the callback returns null, the new node appears directly at
  /// its final position.
  Offset? Function(NodeBase node)? spawnPositionResolver;

  /// { @nodoc }
  Set<N> get nodes => Set.unmodifiable(_nodes);

  /// { @nodoc }
  Set<E> get edges => Set.unmodifiable(_edges);

  /// Returns the current layout. Throws [StateError]
  /// if the graph is not laid out yet.
  GraphLayout get layout =>
      _layout ?? (throw StateError('Graph is not laid out yet'));

  /// Return the current size of the graph canvas. Throws [StateError]
  /// if the size is not available yet.
  Size get canvasSize =>
      _currentSize ?? (throw StateError('Size is not available yet'));

  /// Checks whether the graph is laid out and the size is available.
  bool get canLayout => _layout != null && _currentSize != null;

  /// True while a layout interpolation tween is running.
  bool get isLayoutTransitioning =>
      _transitionFrom != null && _transitionTarget != null;

  /// True while relayout is in flight or a layout transition is animating.
  bool get isLayoutSettling => _relayoutInFlight || isLayoutTransitioning;

  /// True while a node drag owns the pointer sequence and camera pan/zoom
  /// should stay disabled.
  bool get isCameraGated => _cameraGated;

  /// Number of times [_relayout] has started. For tests only.
  @visibleForTesting
  int get relayoutInvocationCount => _relayoutInvocationCount;

  /// Overrides the layout position of [node] for presentation only.
  ///
  /// Does not mutate the graph or trigger relayout. Stops any in-progress layout
  /// transition animation.
  void setNodePresentationPosition(NodeBase node, Offset position) {
    final typedNode = _typedNode(node);
    _stopLayoutAnimation();
    _presentationPositions[typedNode] = position;
    notifyListeners();
  }

  /// Clears the presentation override for [node], if any.
  void clearPresentationPosition(NodeBase node) {
    if (_presentationPositions.remove(_typedNode(node)) != null) {
      notifyListeners();
    }
  }

  /// Clears every presentation override.
  void clearAllPresentationPositions() {
    if (_presentationPositions.isEmpty) {
      return;
    }
    _presentationPositions.clear();
    notifyListeners();
  }

  /// Returns the displayed centre of [node], including any presentation override.
  Offset getPosition(NodeBase node) =>
      _presentationPositions[_typedNode(node)] ??
      layout.getPosition(_typedNode(node));

  /// Like [getPosition] but returns null when the node has no layout position.
  Offset? getPositionOrNull(NodeBase node) =>
      _presentationPositions[_typedNode(node)] ??
      layout.getPositionOrNull(_typedNode(node));

  /// Converts a point in viewport-local coordinates to canvas/scene space.
  Offset viewportLocalToScene(Offset viewportLocal) {
    final transformation = _transformationController;
    if (transformation == null) {
      return viewportLocal;
    }
    final matrix = transformation.value.clone()..invert();
    return MatrixUtils.transformPoint(matrix, viewportLocal);
  }

  /// Converts a canvas/scene point to viewport-local coordinates.
  Offset sceneToViewportLocal(Offset scene) {
    final transformation = _transformationController;
    if (transformation == null) {
      return scene;
    }
    return MatrixUtils.transformPoint(transformation.value, scene);
  }

  /// Orders [nodes] for painting, labelling, and hit testing.
  ///
  /// When [paintOrder] is null or empty, iteration order is preserved.
  Iterable<N> orderedNodes(
    Iterable<N> nodes, {
    List<NodeBase>? paintOrder,
  }) {
    if (paintOrder == null || paintOrder.isEmpty) {
      return nodes;
    }

    final remaining = nodes.toSet();
    final ordered = <N>[];
    for (final node in paintOrder) {
      if (node is N && remaining.remove(node)) {
        ordered.add(node);
      }
    }
    ordered.addAll(remaining);
    return ordered;
  }

  /// Updates the graph using [GraphMutator]. Initiates relayout.
  void mutate(void Function(GraphMutator<N, E> mutator) callback) {
    callback(GraphMutator<N, E>(this));
    _currentSize = _size?.resolve(nodes: nodes, edges: edges);
    _relayout();
  }

  /// Returns s set of nodes that are currently visible on the screen
  /// according to the provided [LazyBuilding].
  ///
  /// Nodes without a layout position are always excluded: a node added in
  /// the current frame has no position until the async relayout emits, and
  /// rendering it would hit the null assert inside [GraphLayout.getPosition].
  Set<N> getVisibleNodes() {
    final viewport = _effectiveViewport;
    final layout = _layout;
    if (viewport == null || layout == null) return {};
    if (viewport == Rect.largest) {
      return _nodes.where((node) => getPositionOrNull(node) != null).toSet();
    }

    return _nodes.where(
      (node) {
        final position = getPositionOrNull(node);
        if (position == null) {
          return false;
        }
        return viewport.containsNode(
          node,
          position,
        );
      },
    ).toSet();
  }

  /// { @nodoc }
  void jumpToCenter() {
    jumpToPosition(canvasSize.center(Offset.zero));
  }

  /// Instantly jumps to the given position on canvas.
  ///
  /// When [resetScale] is true, zoom is restored to 1.0 (the default).
  void jumpToPosition(Offset position, {bool resetScale = false}) {
    final controller = _transformationController;
    final pixel = _viewportPixelSize;
    if (controller == null || pixel == null) {
      return;
    }

    final oldScale = controller.value.getMaxScaleOnAxis();
    final matrixScale = resetScale ? 1.0 : oldScale;

    controller.value = Matrix4.identity()
      ..translate(pixel.width / 2, pixel.height / 2)
      ..scale(matrixScale)
      ..translate(-position.dx, -position.dy);
    _syncActualViewportFromPixelSize();
  }

  /// Instantly jumps to the given node placing it in the center of the screen.
  ///
  /// When [resetScale] is true, zoom is restored to 1.0 (the default).
  FutureOr<void> jumpToNode(N node, {bool resetScale = false}) async {
    if (!_hasNode(node)) {
      throw ArgumentError.value(node, 'node', 'Node is not in the graph');
    }

    if (_layout == null) {
      await Future<void>.delayed(Duration.zero);

      if (_layout == null) {
        throw StateError('Graph is not laid out yet');
      }
    }
    jumpToPosition(_layout!.getPosition(node), resetScale: resetScale);
  }

  /// Instantly zoom in by a given factor.
  void zoomIn([double factor = 1.2]) => zoomBy(factor);

  /// Instantly zoom out by a given factor.
  void zoomOut([double factor = 1 / 1.2]) => zoomBy(factor);

  /// Instantly zooms by a given factor.
  void zoomBy(double factor) {
    if (factor <= 0) {
      throw ArgumentError.value(factor, 'factor', 'Factor must be > 0');
    }

    final controller = _transformationController;
    final viewport = _actualViewport;
    if (controller == null || viewport == null) {
      return;
    }

    final currentScale = controller.value.getMaxScaleOnAxis();
    final desiredScale =
        (currentScale * factor).clamp(_boundaryMinScale(), _maxScale);
    final effectiveFactor = desiredScale / currentScale;
    if (effectiveFactor == 1.0) {
      return;
    }

    final oldMatrix = controller.value.clone();
    final center = viewport.center;

    controller.value = oldMatrix
      ..translate(center.dx, center.dy)
      ..scale(effectiveFactor)
      ..translate(-center.dx, -center.dy);
    _syncActualViewportFromPixelSize();
  }

  /// Fits [rect] (in canvas coordinates) into the viewport.
  void fitToRect(Rect rect, {double padding = 48}) {
    final transformation = _transformationController;
    final pixel = _viewportPixelSize;
    if (transformation == null || pixel == null) {
      return;
    }

    final padded = rect.inflate(padding);
    if (padded.width <= 0 || padded.height <= 0) {
      return;
    }

    final viewportWidth = pixel.width;
    final viewportHeight = pixel.height;

    final scale = math
        .min(viewportWidth / padded.width, viewportHeight / padded.height)
        .clamp(_boundaryMinScale(), _maxScale)
        .toDouble();

    final center = padded.center;
    transformation.value = Matrix4.identity()
      ..translate(viewportWidth / 2, viewportHeight / 2)
      ..scale(scale)
      ..translate(-center.dx, -center.dy);
    _syncActualViewportFromPixelSize();
  }

  /// Fits every node of [nodes] that has a position into the viewport.
  /// Nodes without a position (not laid out yet) are ignored.
  void fitToNodes(Iterable<NodeBase> nodes, {double padding = 48}) {
    final layout = _layout;
    if (layout == null) {
      return;
    }

    Rect? bounds;
    for (final node in nodes) {
      final position = layout.getPositionOrNull(node);
      if (position == null) {
        continue;
      }
      final nodeRect = Rect.fromCenter(
        center: position,
        width: node.size,
        height: node.size,
      );
      bounds = bounds == null ? nodeRect : bounds.expandToInclude(nodeRect);
    }

    if (bounds == null) {
      return;
    }
    fitToRect(bounds, padding: padding);
  }

  /// { @nodoc }
  void replaceNode(N node, N newNode) {
    _replaceNode(node, newNode);
  }

  /// { @nodoc }
  void setPinned(N node, bool pinned) {
    _replaceNode(node, node.copyWithPinned(pinned) as N);
  }

  Future<void> _relayout() async {
    final currentAlgorithm = _currentAlgorithm;
    final currentSize = _currentSize;
    final layout = _layout;

    if (currentAlgorithm == null || currentSize == null) {
      return;
    }

    _relayoutInvocationCount++;
    final generation = ++_relayoutGeneration;
    _relayoutInFlight = true;
    notifyListeners();
    final nodesSnapshot = Set<N>.of(_nodes);
    final edgesSnapshot = Set<E>.of(_edges);

    final layoutStream = layout == null
        ? currentAlgorithm.layout(
            nodes: nodesSnapshot,
            edges: edgesSnapshot,
            size: currentSize,
          )
        : currentAlgorithm.relayout(
            existingLayout: layout,
            nodes: nodesSnapshot,
            edges: edgesSnapshot,
            size: currentSize,
          );

    try {
      await for (final layout in layoutStream) {
        if (generation != _relayoutGeneration) {
          return;
        }
        _publishLayout(layout);
      }
    } finally {
      if (generation == _relayoutGeneration) {
        _relayoutInFlight = false;
        notifyListeners();
      }
    }
  }

  void _stopLayoutAnimation() {
    _ticker?.stop();
    final target = _transitionTarget;
    if (target != null) {
      _layout = target;
    }
    _transitionFrom = null;
    _transitionTarget = null;
  }

  void _setCameraGated(bool gated) {
    if (_cameraGated == gated) {
      return;
    }
    _cameraGated = gated;
    notifyListeners();
  }

  /// Stops an in-progress layout transition without relayout.
  ///
  /// Used by the optional node-drag layer when a pointer capture begins.
  void stopLayoutAnimationForInteraction() {
    _stopLayoutAnimation();
    notifyListeners();
  }

  /// Gates or releases camera pan/zoom for an active node-drag sequence.
  void setCameraInteractionGated(bool gated) => _setCameraGated(gated);

  /// Single funnel through which every new layout reaches the renderer.
  void _publishLayout(GraphLayout next) {
    if (_transitionDuration == Duration.zero ||
        _layout == null ||
        _ticker == null) {
      _layout = next;
      notifyListeners();
      return;
    }

    _transitionFrom = _layout;
    _transitionTarget = next;
    _ticker!
      ..stop()
      ..start();
    notifyListeners();
  }

  void _onTransitionTick(Duration elapsed) {
    final from = _transitionFrom;
    final target = _transitionTarget;
    if (from == null || target == null) {
      _ticker?.stop();
      return;
    }

    final total = _transitionDuration.inMicroseconds;
    final t = total <= 0
        ? 1.0
        : (elapsed.inMicroseconds / total).clamp(0.0, 1.0).toDouble();

    _layout = GraphLayout.lerp(
      from,
      target,
      _transitionCurve.transform(t),
      spawn: spawnPositionResolver,
    );

    if (t >= 1.0) {
      _layout = target;
      _transitionFrom = null;
      _transitionTarget = null;
      _ticker?.stop();
    }
    notifyListeners();
  }

  /// Minimum scale [InteractiveViewer] allows with [EdgeInsets.zero] margins.
  double _boundaryMinScale() {
    final pixel = _viewportPixelSize;
    final size = _currentSize;
    if (pixel == null ||
        size == null ||
        size.width <= 0 ||
        size.height <= 0) {
      return _minScale;
    }
    final floor = math.max(pixel.width / size.width, pixel.height / size.height);
    return math.max(_minScale, floor);
  }

  void _syncActualViewportFromPixelSize() {
    final pixel = _viewportPixelSize;
    final transformation = _transformationController;
    if (pixel == null || transformation == null) {
      return;
    }
    final scale = transformation.value.getMaxScaleOnAxis();
    if (scale == 0) {
      return;
    }
    final matrix = transformation.value.clone()..invert();
    final topLeft = MatrixUtils.transformPoint(matrix, Offset.zero);
    final bottomRight = MatrixUtils.transformPoint(
      matrix,
      Offset(pixel.width, pixel.height),
    );
    _actualViewport = Rect.fromPoints(topLeft, bottomRight);
  }

  @visibleForTesting
  double get currentScale {
    final transformation = _transformationController;
    if (transformation == null) {
      throw StateError('GraphController is not attached to a GraphView');
    }
    return transformation.value.getMaxScaleOnAxis();
  }

  void _detachTicker() {
    _ticker?.dispose();
    _ticker = null;
    final target = _transitionTarget;
    if (target != null) {
      _layout = target;
    }
    _transitionFrom = null;
    _transitionTarget = null;
  }

  Future<void> _applyConfiguration({
    required GraphLayoutAlgorithm algorithm,
    required GraphCanvasSize size,
    required LazyBuilding lazyBuilding,
    required TransformationController transformationController,
    required TickerProvider vsync,
    required Duration transitionDuration,
    required Curve transitionCurve,
    required double minScale,
    required double maxScale,
  }) async {
    _transitionDuration = transitionDuration;
    _transitionCurve = transitionCurve;
    _minScale = minScale;
    _maxScale = maxScale;
    _ticker?.dispose();
    _ticker = vsync.createTicker(_onTransitionTick);

    _lazyBuilding = lazyBuilding;
    _transformationController = transformationController;
    _currentAlgorithm = algorithm;
    _size = size;
    _currentSize = _size?.resolve(nodes: nodes, edges: edges);
    final generation = ++_relayoutGeneration;
    final nodesSnapshot = Set<N>.of(_nodes);
    final edgesSnapshot = Set<E>.of(_edges);
    final layoutStream = algorithm.layout(
      nodes: nodesSnapshot,
      edges: edgesSnapshot,
      size: canvasSize,
    );

    await for (final layout in layoutStream) {
      if (generation != _relayoutGeneration) {
        return;
      }
      _publishLayout(layout);

      if (!_centered) {
        jumpToCenter();
        _centered = true;
      }
    }
  }

  void _updateViewport(Quad viewport) {
    final rect = viewport.toRect();
    _actualViewport = rect;
    final scale = _transformationController?.value.getMaxScaleOnAxis() ?? 1.0;
    _viewportPixelSize = Size(rect.width * scale, rect.height * scale);
    final actualViewport = rect;
    final newEffectiveViewport = switch (_lazyBuilding) {
      LazyBuildingViewport(scale: final scale) => actualViewport.scale(scale),
      LazyBuildingNone() || null => Rect.largest,
    };

    // If the new viewport is contained in the current effective viewport,
    // then skip the update to avoid unnecessary rebuilds
    if (_effectiveViewport != null &&
        _effectiveViewport!.containsRect(actualViewport)) {
      return;
    } else {
      _effectiveViewport = newEffectiveViewport;
      notifyListeners();
    }
  }

  void _addNode(N node) {
    if (_hasNode(node)) {
      throw StateError('Node is already in the graph');
    }
    _nodes.add(node);
  }

  void _removeNode(N node) {
    if (!_hasNode(node)) {
      throw StateError('Node $node is not in the graph');
    }
    _edges
        .removeWhere((edge) => edge.source == node || edge.destination == node);
    _nodes.remove(node);
  }

  void _addEdge(E edge) {
    if (!_hasNode(edge.source) || !_hasNode(edge.destination)) {
      throw StateError('Source or destination node is not in the graph');
    }
    _edges.add(edge);
  }

  void _removeEdge(E edge) {
    if (!_hasEdge(edge)) {
      throw StateError('Edge $edge is not in the graph');
    }
    _edges.remove(edge);
  }

  /// Pins or unpins the node. Pinned nodes should not be affected by layout.
  void _replaceNode(N node, N newNode) {
    if (!_hasNode(node)) {
      throw ArgumentError.value(node, 'node', 'Node is not in the graph');
    }

    _nodes
      ..remove(node)
      ..add(newNode);

    if (_layout != null) {
      final position = _layout!.getPosition(node);
      final builder = GraphLayoutBuilder.fromLayout(_layout!)
        ..removeNode(node)
        ..addNode(newNode)
        ..setNodePosition(newNode, position);
      _layout = builder.build();
    }

    final edgesCopy = Set.of(_edges);

    for (final edge in edgesCopy) {
      if (edge.source == node) {
        _edges
          ..remove(edge)
          ..add(edge.replaceNode(source: newNode) as E);
      }
      if (edge.destination == node) {
        _edges
          ..remove(edge)
          ..add(edge.replaceNode(destination: newNode) as E);
      }
    }

    notifyListeners();
  }

  /// Removes every node and edge. When [recenter] is true the next layout
  /// re-centres the viewport, as if the graph had just been created.
  void clear({bool recenter = true}) {
    _nodes.clear();
    _edges.clear();
    _layout = null;
    _presentationPositions.clear();
    _cameraGated = false;
    _transitionFrom = null;
    _transitionTarget = null;
    _ticker?.stop();
    if (recenter) {
      _centered = false;
    }
    notifyListeners();
  }

  var _deferredNotifyPending = false;

  @override
  void notifyListeners() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      if (_deferredNotifyPending) {
        return;
      }
      _deferredNotifyPending = true;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        _deferredNotifyPending = false;
        if (!hasListeners) {
          return;
        }
        super.notifyListeners();
      });
      return;
    }
    super.notifyListeners();
  }

  @override
  void dispose() {
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }

  bool _hasNode(N node) => _nodes.contains(node);

  bool _hasEdge(E edge) => _edges.contains(edge);

  N _typedNode(NodeBase node) {
    if (!_hasNode(node as N)) {
      throw ArgumentError.value(node, 'node', 'Node is not in the graph');
    }
    return node as N;
  }
}

/// Wrapper around [GraphController] that allows
/// changing the graph in a batch to avoid unnecessary rebuilds.
class GraphMutator<N extends NodeBase, E extends EdgeBase<N>> {
  /// { @nodoc }
  GraphMutator(this.controller);

  /// { @nodoc }
  final GraphController controller;

  /// { @nodoc }
  void addNode(N node) {
    controller._addNode(node);
  }

  /// { @nodoc }
  void addEdge(E edge) {
    controller._addEdge(edge);
  }

  /// { @nodoc }
  void removeNode(N node) {
    controller._removeNode(node);
  }

  /// { @nodoc }
  void removeEdge(E edge) {
    controller._removeEdge(edge);
  }

  /// { @nodoc }
  void clear() {
    controller.clear();
  }
}
