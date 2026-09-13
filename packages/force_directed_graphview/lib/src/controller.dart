part of 'graph_view.dart';

/// Controller to manipulate the [GraphView].
class GraphController<N extends NodeBase, E extends EdgeBase<N>>
    with ChangeNotifier {
  /// { @nodoc }
  GraphController({
    required GraphNodeIdResolver<N> nodeIdOf,
    required GraphEdgeIdResolver<E> edgeIdOf,
  })  : _nodeIdOf = nodeIdOf,
        _edgeIdOf = edgeIdOf {
    _scene.addListener(_onSceneStateChanged);
  }

  final GraphNodeIdResolver<N> _nodeIdOf;
  final GraphEdgeIdResolver<E> _edgeIdOf;
  final GraphSceneController<N, E> _scene = GraphSceneController<N, E>();

  final _nodes = <N>{};
  final _edges = <E>{};

  // Region of canvas that is building its nodes now
  Rect? _effectiveViewport;
  Rect? _actualViewport;
  Size? _viewportPixelSize;
  SceneLayoutAlgorithm? _currentAlgorithm;
  LazyBuilding? _lazyBuilding;
  TransformationController? _transformationController;
  GraphCanvasSize? _size;
  Size? _lastViewportSceneSize;
  Size? _lastLayoutConstraints;

  Size? _currentSize;
  var _centered = false;
  var _relayoutInFlight = false;
  var _relayoutInvocationCount = 0;
  GraphLayoutTicket? _lastHandledLayoutSuccessTicket;
  var _cameraGated = false;
  Ticker? _ticker;
  Map<GraphNodeId, ScenePoint>? _transitionFrom;
  Map<GraphNodeId, ScenePoint>? _transitionTarget;
  Map<GraphNodeId, ScenePoint>? _layoutTransitionCapture;
  GraphLayoutTicket? _transitionLayoutTicket;
  Object? _viewOwner;
  VoidCallback? _gestureAbortCallback;
  Duration _transitionDuration = Duration.zero;
  Curve _transitionCurve = Curves.easeOutCubic;
  double _minScale = 0.5;
  double _maxScale = 2;

  /// Resolves where a node that is new to the layout should start its transition.
  /// Set by the owner (e.g. "the node the user just expanded"). When the field
  /// is null, or the callback returns null, the new node appears directly at
  /// its final position.
  Offset? Function(GraphNodeId nodeId)? spawnPositionResolver;

  /// { @nodoc }
  Set<N> get nodes => Set.unmodifiable(_nodes);

  /// { @nodoc }
  Set<E> get edges => Set.unmodifiable(_edges);

  /// Return the current size of the graph canvas. Throws [StateError]
  /// if the size is not available yet.
  Size get canvasSize =>
      _currentSize ?? (throw StateError('Size is not available yet'));

  /// Checks whether the graph is laid out and the size is available.
  bool get canLayout {
    if (_currentSize == null || _nodes.isEmpty) {
      return false;
    }
    final snapshot = _scene.snapshot;
    if (snapshot.layout == null) {
      return false;
    }
    for (final id in snapshot.topology.nodesById.keys) {
      if (snapshot.resolvePosition(id) == null) {
        return false;
      }
    }
    return true;
  }

  /// True while a layout interpolation tween is running.
  bool get isLayoutTransitioning =>
      _transitionFrom != null &&
      _transitionTarget != null &&
      _scene.snapshot.transition != null;

  /// True while relayout is in flight or a layout transition is animating.
  bool get isLayoutSettling => _relayoutInFlight || isLayoutTransitioning;

  /// True while a node drag owns the pointer sequence and camera pan/zoom
  /// should stay disabled.
  bool get isCameraGated => _cameraGated;

  /// Stable node id resolver required for scene topology.
  GraphNodeIdResolver<N> get nodeIdOf => _nodeIdOf;

  /// Stable edge id resolver required for scene topology.
  GraphEdgeIdResolver<E> get edgeIdOf => _edgeIdOf;

  /// ID-keyed scene state owned by this controller.
  @visibleForTesting
  GraphSceneController<N, E> get scene => _scene;

  /// Number of times [_requestSceneLayout] has started. For tests only.
  @visibleForTesting
  int get relayoutInvocationCount => _relayoutInvocationCount;

  /// Clears the presentation override for [id], if any.
  void clearPresentationForNodeId(GraphNodeId id) {
    _scene.clearPresentationForNode(id);
  }

  /// Clears every presentation override.
  void clearAllPresentationPositions() {
    _scene.clearAllPresentationOverrides();
  }

  /// Returns the displayed centre of [node], including any presentation override.
  Offset getPosition(N node) {
    final point = _scene.resolvePosition(_nodeIdOf(node));
    if (point == null) {
      throw StateError('Node has no layout position yet');
    }
    return Offset(point.x, point.y);
  }

  /// Like [getPosition] but returns null when the node has no layout position.
  Offset? getPositionOrNull(N node) {
    final point = _scene.resolvePosition(_nodeIdOf(node));
    if (point == null) {
      return null;
    }
    return Offset(point.x, point.y);
  }

  /// Instantly centers the viewport on [id] when it has a resolved position.
  FutureOr<void> jumpToNodeId(GraphNodeId id, {bool resetScale = false}) {
    final point = _scene.resolvePosition(id);
    if (point == null) {
      throw StateError('Node $id is not laid out yet');
    }
    jumpToPosition(Offset(point.x, point.y), resetScale: resetScale);
  }

  /// Fits every node in [ids] that has a resolved position into the viewport.
  void fitToNodeIds(Iterable<GraphNodeId> ids, {double padding = 48}) {
    Rect? bounds;
    final snapshot = _scene.snapshot;
    for (final id in ids) {
      final point = snapshot.resolvePosition(id);
      final sceneNode = snapshot.topology.nodesById[id];
      if (point == null || sceneNode == null) {
        continue;
      }
      final radius = sceneNode.size.width / 2;
      final nodeRect = Rect.fromCircle(
        center: Offset(point.x, point.y),
        radius: radius,
      );
      bounds = bounds == null ? nodeRect : bounds.expandToInclude(nodeRect);
    }
    if (bounds == null) {
      return;
    }
    fitToRect(bounds, padding: padding);
  }

  /// Replaces configured paint/hit order for visible nodes.
  void setNodePaintOrder(List<GraphNodeId> order) {
    _scene.setPaintOrder(order);
    notifyListeners();
  }

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

  /// Updates the graph using [GraphMutator]. Initiates relayout when topology
  /// changes or [requestLayout] is true.
  void mutate(
    void Function(GraphMutator<N, E> mutator) callback, {
    bool requestLayout = true,
  }) {
    callback(GraphMutator<N, E>(this));
    _commitTopologyChange(requestLayout: requestLayout);
  }

  /// Replaces nodes and edges by stable id without clearing the camera.
  void reconcileTopology(
    Set<N> targetNodes,
    Set<E> targetEdges, {
    bool requestLayout = false,
    bool layoutOnTopologyChange = true,
  }) {
    _replaceNodeAndEdgeSets(targetNodes, targetEdges);
    _commitTopologyChange(
      requestLayout: requestLayout,
      layoutOnTopologyChange: layoutOnTopologyChange,
    );
  }

  /// Requests scene layout for the current topology and algorithm.
  GraphLayoutTicket? requestSceneLayout({
    Set<GraphPresentationToken> releaseOnTerminal = const {},
  }) {
    final currentAlgorithm = _currentAlgorithm;
    final currentSize = _currentSize;
    if (currentAlgorithm == null || currentSize == null || _nodes.isEmpty) {
      return null;
    }

    _layoutTransitionCapture = _captureDisplayedPositions();
    _relayoutInvocationCount++;
    _relayoutInFlight = true;
    notifyListeners();

    return _scene.requestLayout(
      currentAlgorithm,
      canvasSize: SceneSize(
        width: currentSize.width,
        height: currentSize.height,
      ),
      releaseOnTerminal: releaseOnTerminal,
    );
  }

  /// Active presentation drag token for [id], if any.
  GraphPresentationToken? activePresentationTokenForNode(GraphNodeId id) =>
      _scene.activePresentationTokenForNode(id);

  void _commitTopologyChange({
    required bool requestLayout,
    bool layoutOnTopologyChange = true,
  }) {
    _currentSize = _size?.resolve(nodes: nodes, edges: edges);
    final revisionBefore = _scene.topologyRevision;
    _applyTopologyFromController();
    final topologyChanged = _scene.topologyRevision != revisionBefore;
    if (requestLayout || (layoutOnTopologyChange && topologyChanged)) {
      _requestSceneLayout();
    } else {
      notifyListeners();
    }
  }

  void _replaceNodeAndEdgeSets(Set<N> targetNodes, Set<E> targetEdges) {
    final targetNodesById = {for (final node in targetNodes) _nodeIdOf(node): node};
    final targetEdgesById = {for (final edge in targetEdges) _edgeIdOf(edge): edge};

    _nodes.removeWhere((node) => !targetNodesById.containsKey(_nodeIdOf(node)));
    for (final entry in targetNodesById.entries) {
      final existing = _nodes
          .cast<N?>()
          .where((node) => node != null && _nodeIdOf(node!) == entry.key)
          .firstOrNull;
      if (existing == null) {
        _nodes.add(entry.value);
      } else if (existing != entry.value) {
        _nodes.remove(existing);
        _nodes.add(entry.value);
      }
    }

    _edges.removeWhere((edge) => !targetEdgesById.containsKey(_edgeIdOf(edge)));
    for (final entry in targetEdgesById.entries) {
      final existing = _edges
          .cast<E?>()
          .where((edge) => edge != null && _edgeIdOf(edge!) == entry.key)
          .firstOrNull;
      if (existing == null) {
        _edges.add(entry.value);
      } else if (existing != entry.value) {
        _edges.remove(existing);
        _edges.add(entry.value);
      }
    }
  }

  /// Uses [algorithm] for the next layout request.
  ///
  /// GraphView also applies its widget algorithm on configuration changes;
  /// call this before [mutate] when the owner already knows the new layout
  /// inputs and cannot wait for the next widget rebuild.
  void useSceneLayoutAlgorithm(SceneLayoutAlgorithm algorithm) {
    _currentAlgorithm = algorithm;
  }

  /// Immutable scene state for one render, hit-test, or drag pass.
  GraphSceneSnapshot<N, E> get renderSnapshot => _scene.snapshot;

  /// Visible node ids for [snapshot], recomputed from resolved positions and
  /// lazy viewport policy on every call.
  Set<GraphNodeId> visibleNodeIds(GraphSceneSnapshot<N, E> snapshot) {
    final viewport = _effectiveViewport;
    if (!canLayout) {
      return const {};
    }
    if (viewport == null) {
      return {
        for (final id in snapshot.topology.nodesById.keys)
          if (snapshot.resolvePosition(id) != null) id,
      };
    }
    if (viewport == Rect.largest) {
      return {
        for (final id in snapshot.topology.nodesById.keys)
          if (snapshot.resolvePosition(id) != null) id,
      };
    }

    final visible = <GraphNodeId>{};
    for (final entry in snapshot.topology.nodesById.entries) {
      final point = snapshot.resolvePosition(entry.key);
      if (point == null) {
        continue;
      }
      final center = Offset(point.x, point.y);
      final radius = entry.value.size.width / 2;
      final nodeRect = Rect.fromCircle(center: center, radius: radius);
      if (nodeRect.overlaps(viewport)) {
        visible.add(entry.key);
      }
    }
    return visible;
  }

  /// Paint and hit-test order for visible nodes in [snapshot].
  ///
  /// Active presentation overrides paint on top without mutating topology.
  List<GraphNodeId> orderedRenderNodeIds(
    GraphSceneSnapshot<N, E> snapshot, {
    List<GraphNodeId>? configuredPaintOrder,
  }) {
    final visible = visibleNodeIds(snapshot);
    if (visible.isEmpty) {
      return const [];
    }

    final ordered = <GraphNodeId>[];
    final remaining = visible.toSet();

    final paintOrder = configuredPaintOrder ?? snapshot.presentation.paintOrder;
    if (paintOrder.isNotEmpty) {
      for (final id in paintOrder) {
        if (remaining.remove(id)) {
          ordered.add(id);
        }
      }
    }

    for (final id in snapshot.topology.nodesById.keys) {
      if (remaining.remove(id)) {
        ordered.add(id);
      }
    }

    for (final id in snapshot.presentation.overrides.keys) {
      if (!visible.contains(id)) {
        continue;
      }
      ordered
        ..remove(id)
        ..add(id);
    }

    return ordered;
  }

  /// Resolves the current payload for [id] at a compatibility boundary.
  N? nodePayloadForId(GraphNodeId id) =>
      _scene.snapshot.topology.nodesById[id]?.payload;

  /// Starts a token-owned presentation drag for [node].
  GraphPresentationToken beginNodePresentationDrag(N node, Offset position) {
    _freezeLayoutTransitionAtDisplay();
    return _scene.beginPresentation(
      _nodeIdOf(node),
      ScenePoint(x: position.dx, y: position.dy),
    );
  }

  /// Updates an active presentation drag identified by [token].
  bool updateNodePresentationDrag(
    GraphPresentationToken token,
    Offset position,
  ) =>
      _scene.updatePresentation(
        token,
        ScenePoint(x: position.dx, y: position.dy),
      );

  /// Cancels an active presentation drag identified by [token].
  bool cancelNodePresentationDrag(GraphPresentationToken token) =>
      _scene.cancelPresentation(token);

  /// Returns s set of nodes that are currently visible on the screen
  /// according to the provided [LazyBuilding].
  ///
  /// Nodes without a layout position are always excluded: a node added in
  /// the current frame has no position until the async relayout emits.
  Set<N> getVisibleNodes() {
    final snapshot = renderSnapshot;
    return visibleNodeIds(snapshot)
        .map((id) => snapshot.topology.nodesById[id]!.payload)
        .toSet();
  }

  /// { @nodoc }
  void jumpToCenter() {
    jumpToPosition(canvasSize.center(Offset.zero));
  }

  /// Instantly jumps to the given position on canvas.
  ///
  /// When [resetScale] is true, zoom is restored to 1.0 (the default).
  void jumpToPosition(Offset position, {bool resetScale = false}) {
    _abortActiveGesturesIfCameraGated();
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

    if (!canLayout) {
      await Future<void>.delayed(Duration.zero);
      if (!canLayout) {
        throw StateError('Graph is not laid out yet');
      }
    }
    jumpToNodeId(_nodeIdOf(node), resetScale: resetScale);
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

    _abortActiveGesturesIfCameraGated();
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
    _abortActiveGesturesIfCameraGated();
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
  void fitToNodes(Iterable<N> nodes, {double padding = 48}) {
    fitToNodeIds(nodes.map(_nodeIdOf), padding: padding);
  }

  /// { @nodoc }
  void replaceNode(N node, N newNode) {
    _replaceNode(node, newNode);
  }

  /// { @nodoc }
  void setPinned(N node, bool pinned) {
    _replaceNode(node, node.copyWithPinned(pinned) as N);
  }

  void _requestSceneLayout() {
    final currentAlgorithm = _currentAlgorithm;
    final currentSize = _currentSize;

    if (currentAlgorithm == null || currentSize == null) {
      return;
    }

    requestSceneLayout();
  }

  void _onSceneStateChanged() {
    _relayoutInFlight = _scene.layoutOutcome is GraphLayoutOutcomeRunning;
    final outcome = _scene.layoutOutcome;
    GraphLayoutTicket? successTicket;
    Map<GraphNodeId, ScenePoint>? acceptedPositions;
    if (outcome is GraphLayoutOutcomeSucceeded) {
      successTicket = outcome.ticket;
      final layout = _scene.snapshot.layout;
      if (layout != null && layout.ticket == successTicket) {
        acceptedPositions = layout.positions;
      }
    }
    final isNewLayoutSuccess = successTicket != null &&
        successTicket != _lastHandledLayoutSuccessTicket;
    final shouldCenterAfterLayout =
        outcome is GraphLayoutOutcomeSucceeded && !_centered;

    if (isNewLayoutSuccess) {
      _ticker?.stop();
      _transitionFrom = null;
      _transitionTarget = null;
      _transitionLayoutTicket = null;
    }

    void apply() {
      if (_disposed) {
        return;
      }
      if (isNewLayoutSuccess && acceptedPositions != null) {
        _lastHandledLayoutSuccessTicket = successTicket;
        _handleAcceptedLayout(acceptedPositions);
      }
      if (shouldCenterAfterLayout && canLayout) {
        jumpToCenter();
        _centered = true;
      }
      notifyListeners();
    }

    scheduleMicrotask(apply);
  }

  void _handleAcceptedLayout(Map<GraphNodeId, ScenePoint> target) {
    _ticker?.stop();
    if (_transitionDuration == Duration.zero || _ticker == null) {
      _scene.setLayoutTransition(null);
      _transitionFrom = null;
      _transitionTarget = null;
      _transitionLayoutTicket = null;
      _layoutTransitionCapture = null;
      return;
    }

    final from = _layoutTransitionCapture ?? _captureDisplayedPositions();
    _layoutTransitionCapture = null;
    if (from.isEmpty) {
      _scene.setLayoutTransition(null);
      _transitionLayoutTicket = null;
      return;
    }
    _transitionFrom = from;
    _transitionTarget = target;
    _transitionLayoutTicket = _scene.snapshot.layout?.ticket;
    _scene.setLayoutTransition(from);
    _ticker!
      ..stop()
      ..start();
  }

  Map<GraphNodeId, ScenePoint> _captureDisplayedPositions() {
    final snapshot = _scene.snapshot;
    final positions = <GraphNodeId, ScenePoint>{};
    for (final id in snapshot.topology.nodesById.keys) {
      final point = snapshot.resolvePosition(id);
      if (point != null) {
        positions[id] = point;
      }
    }
    return positions;
  }

  void _applyTopologyFromController({
    Map<GraphNodeId, ScenePoint> initialPositions = const {},
  }) {
    if (_nodes.isEmpty) {
      _scene.applyTopology(
        GraphTopology<N, E>.fromEntries(
          nodes: const [],
          edges: const [],
        ),
      );
      return;
    }

    _scene.applyTopology(
      _topologyFromController(),
      initialPositions: {
        ..._canvasCenterSeedsForNewNodes(),
        ...initialPositions,
      },
    );
  }

  Map<GraphNodeId, ScenePoint> _canvasCenterSeedsForNewNodes() {
    final size = _currentSize;
    if (size == null) {
      return const {};
    }
    final previousIds = _scene.snapshot.topology.nodesById.keys.toSet();
    final nextIds = _nodes.map(_nodeIdOf).toSet();
    final added = nextIds.difference(previousIds);
    if (added.isEmpty) {
      return const {};
    }
    final center = ScenePoint(x: size.width / 2, y: size.height / 2);
    return {for (final id in added) id: center};
  }

  GraphTopology<N, E> _topologyFromController() {
    return GraphTopology.fromEntries(
      nodes: [
        for (final node in _nodes)
          GraphSceneNode(
            id: _nodeIdOf(node),
            payload: node,
            size: SceneSize(width: node.size, height: node.size),
            simulationFixed: node.pinned,
          ),
      ],
      edges: [
        for (final edge in _edges)
          GraphSceneEdge(
            id: _edgeIdOf(edge),
            sourceId: _nodeIdOf(edge.source),
            destinationId: _nodeIdOf(edge.destination),
            payload: edge,
          ),
      ],
    );
  }

  void _freezeLayoutTransitionAtDisplay() {
    _ticker?.stop();
    if (_transitionFrom != null ||
        _transitionTarget != null ||
        _scene.snapshot.transition != null) {
      final displayed = _captureDisplayedPositions();
      if (displayed.isNotEmpty) {
        _scene.setLayoutTransition(displayed);
      }
    }
    _transitionFrom = null;
    _transitionTarget = null;
    _transitionLayoutTicket = null;
    _layoutTransitionCapture = null;
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
    _freezeLayoutTransitionAtDisplay();
    notifyListeners();
  }

  /// Gates or releases camera pan/zoom for an active node-drag sequence.
  void setCameraInteractionGated(bool gated) => _setCameraGated(gated);

  void _onTransitionTick(Duration elapsed) {
    final from = _transitionFrom;
    final target = _transitionTarget;
    if (from == null || target == null) {
      _ticker?.stop();
      return;
    }

    final activeLayoutTicket = _scene.snapshot.layout?.ticket;
    if (_transitionLayoutTicket != null &&
        activeLayoutTicket != _transitionLayoutTicket) {
      _ticker?.stop();
      _transitionFrom = null;
      _transitionTarget = null;
      _transitionLayoutTicket = null;
      return;
    }

    final total = _transitionDuration.inMicroseconds;
    final t = total <= 0
        ? 1.0
        : (elapsed.inMicroseconds / total).clamp(0.0, 1.0).toDouble();
    final eased = _transitionCurve.transform(t);

    final interpolated = <GraphNodeId, ScenePoint>{};
    for (final entry in target.entries) {
      final start = from[entry.key] ??
          _spawnScenePoint(entry.key) ??
          entry.value;
      interpolated[entry.key] = ScenePoint(
        x: start.x + (entry.value.x - start.x) * eased,
        y: start.y + (entry.value.y - start.y) * eased,
      );
    }
    _scene.setLayoutTransition(interpolated);

    if (t >= 1.0) {
      _scene.setLayoutTransition(null);
      _transitionFrom = null;
      _transitionTarget = null;
      _transitionLayoutTicket = null;
      _ticker?.stop();
    }
    notifyListeners();
  }

  ScenePoint? _spawnScenePoint(GraphNodeId id) {
    final spawn = spawnPositionResolver;
    if (spawn == null) {
      return null;
    }
    final offset = spawn(id);
    if (offset == null) {
      return null;
    }
    return ScenePoint(x: offset.dx, y: offset.dy);
  }

  /// Minimum scale [InteractiveViewer] allows with [EdgeInsets.zero] margins.
  double _boundaryMinScale() {
    final pixel = _viewportPixelSize;
    final size = _currentSize;
    if (pixel == null || size == null || size.width <= 0 || size.height <= 0) {
      return _minScale;
    }
    final floor =
        math.max(pixel.width / size.width, pixel.height / size.height);
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

  /// Wired by [NodeDragGesture]; not for app callers.
  void registerGestureLifecycleAbort(VoidCallback abort) {
    _gestureAbortCallback = abort;
  }

  /// Wired by [NodeDragGesture]; not for app callers.
  void unregisterGestureLifecycleAbort(VoidCallback abort) {
    if (identical(_gestureAbortCallback, abort)) {
      _gestureAbortCallback = null;
    }
  }

  void _abortActiveGestures() {
    _gestureAbortCallback?.call();
  }

  void _abortActiveGesturesIfCameraGated() {
    if (_cameraGated) {
      _abortActiveGestures();
    }
  }

  void _abortViewGesturesForOwner(Object viewOwner) {
    if (_viewOwner != null && !identical(_viewOwner, viewOwner)) {
      return;
    }
    _abortActiveGestures();
    _clearInteractionPresentationIfGated();
  }

  void _detachViewBinding(Object viewOwner) {
    if (_viewOwner != null && !identical(_viewOwner, viewOwner)) {
      return;
    }
    _abortActiveGestures();
    _clearInteractionPresentationIfGated();
    _viewOwner = null;
    _gestureAbortCallback = null;
    _setCameraGated(false);
    _lastLayoutConstraints = null;
    _lastViewportSceneSize = null;
    _detachTransitionTicker();
  }

  void _clearInteractionPresentationIfGated() {
    if (!_cameraGated) {
      return;
    }
    _scene.clearAllPresentationOverrides();
  }

  void _onLayoutConstraintsChanged(Size constraints) {
    if (_lastLayoutConstraints != null &&
        _lastLayoutConstraints != constraints) {
      _abortActiveGestures();
      _clearInteractionPresentationIfGated();
    }
    _lastLayoutConstraints = constraints;
  }

  /// Exposes layout-constraint resize handling for package tests.
  @visibleForTesting
  void handleLayoutConstraintsChangedForTesting(Size constraints) =>
      _onLayoutConstraintsChanged(constraints);

  void _detachTransitionTicker() {
    _ticker?.dispose();
    _ticker = null;
    _transformationController = null;
    _viewportPixelSize = null;
    _transitionFrom = null;
    _transitionTarget = null;
    _transitionLayoutTicket = null;
    _layoutTransitionCapture = null;
  }

  Future<void> _applyConfiguration({
    required Object viewOwner,
    required SceneLayoutAlgorithm algorithm,
    required GraphCanvasSize size,
    required LazyBuilding lazyBuilding,
    required TransformationController transformationController,
    required TickerProvider vsync,
    required Duration transitionDuration,
    required Curve transitionCurve,
    required double minScale,
    required double maxScale,
  }) async {
    if (_viewOwner != null && !identical(_viewOwner, viewOwner)) {
      throw StateError(
        'GraphController is already attached to another GraphView',
      );
    }
    _viewOwner = viewOwner;

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
    _applyTopologyFromController();
    _requestSceneLayout();
  }

  void _updateViewport(Quad viewport) {
    final rect = viewport.toRect();
    final sceneSize = Size(rect.width, rect.height);
    if (_lastViewportSceneSize != null && _lastViewportSceneSize != sceneSize) {
      _abortActiveGestures();
    }
    _lastViewportSceneSize = sceneSize;
    _actualViewport = rect;
    final scale = _transformationController?.value.getMaxScaleOnAxis() ?? 1.0;
    final previousPixel = _viewportPixelSize;
    _viewportPixelSize = Size(rect.width * scale, rect.height * scale);
    if (previousPixel != null &&
        (previousPixel.width != _viewportPixelSize!.width ||
            previousPixel.height != _viewportPixelSize!.height)) {
      _abortActiveGestures();
    }
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

    ScenePoint? retainedPosition;
    final previousId = _nodeIdOf(node);
    final resolved = _scene.resolvePosition(previousId);
    if (resolved != null) {
      retainedPosition = resolved;
    }

    _nodes
      ..remove(node)
      ..add(newNode);

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

    final initialPositions = <GraphNodeId, ScenePoint>{};
    if (retainedPosition != null) {
      initialPositions[_nodeIdOf(newNode)] = retainedPosition;
    }
    _applyTopologyFromController(initialPositions: initialPositions);
    notifyListeners();
  }

  /// Removes every node and edge without moving the camera.
  void clear() {
    _nodes.clear();
    _edges.clear();
    _scene.setLayoutTransition(null);
    _scene.applyTopology(
      GraphTopology<N, E>.fromEntries(
        nodes: const [],
        edges: const [],
      ),
    );
    _scene.clearAllPresentationOverrides();
    _cameraGated = false;
    _lastHandledLayoutSuccessTicket = null;
    _transitionFrom = null;
    _transitionTarget = null;
    _transitionLayoutTicket = null;
    _layoutTransitionCapture = null;
    _ticker?.stop();
    notifyListeners();
  }

  /// Allows the mounted view to perform one-time initial centering again.
  void resetInitialCentering() {
    _centered = false;
  }

  var _deferredNotifyPending = false;
  var _disposed = false;

  @override
  void notifyListeners() {
    final SchedulerBinding? binding = _schedulerBindingOrNull();
    if (binding != null) {
      final phase = binding.schedulerPhase;
      if (phase == SchedulerPhase.persistentCallbacks ||
          phase == SchedulerPhase.midFrameMicrotasks) {
        if (_deferredNotifyPending) {
          return;
        }
        _deferredNotifyPending = true;
        binding.addPostFrameCallback((_) {
          _deferredNotifyPending = false;
          if (!hasListeners) {
            return;
          }
          super.notifyListeners();
        });
        return;
      }
    }
    super.notifyListeners();
  }

  SchedulerBinding? _schedulerBindingOrNull() {
    try {
      return SchedulerBinding.instance;
    } on Object {
      return null;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scene.removeListener(_onSceneStateChanged);
    _scene.dispose();
    _ticker?.dispose();
    _ticker = null;
    super.dispose();
  }

  bool _hasNode(N node) => _nodes.contains(node);

  bool _hasEdge(E edge) => _edges.contains(edge);

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
