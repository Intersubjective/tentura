part of 'graph_view.dart';

/// Controller to manipulate the [GraphView].
class GraphController<N, E> with ChangeNotifier {
  /// { @nodoc }
  GraphController({
    required GraphNodeIdResolver<N> nodeIdOf,
    required GraphEdgeIdResolver<E> edgeIdOf,
    required GraphNodeSizeResolver<N> nodeSizeOf,
    required GraphNodeSimulationFixedResolver<N> nodeSimulationFixedOf,
    required GraphEdgeSourceResolver<E, N> edgeSourceOf,
    required GraphEdgeDestinationResolver<E, N> edgeDestinationOf,
  })  : _nodeIdOf = nodeIdOf,
        _edgeIdOf = edgeIdOf,
        _nodeSizeOf = nodeSizeOf,
        _nodeSimulationFixedOf = nodeSimulationFixedOf,
        _edgeSourceOf = edgeSourceOf,
        _edgeDestinationOf = edgeDestinationOf {
    _scene.addListener(_onSceneStateChanged);
  }

  final GraphNodeIdResolver<N> _nodeIdOf;
  final GraphEdgeIdResolver<E> _edgeIdOf;
  final GraphNodeSizeResolver<N> _nodeSizeOf;
  final GraphNodeSimulationFixedResolver<N> _nodeSimulationFixedOf;
  final GraphEdgeSourceResolver<E, N> _edgeSourceOf;
  final GraphEdgeDestinationResolver<E, N> _edgeDestinationOf;
  final GraphSceneController<N, E> _scene = GraphSceneController<N, E>();

  final _nodes = <N>{};
  final _edges = <E>{};
  final _nodePositions = <GraphNodeId, _NodePositionListenable>{};

  // Region of canvas that is building its nodes now
  Rect? _effectiveViewport;
  Rect? _actualViewport;
  Size? _viewportPixelSize;
  SceneLayoutAlgorithm? _currentAlgorithm;
  LazyBuilding? _lazyBuilding;
  TransformationController? _transformationController;
  final ValueNotifier<int> _cameraRevision = ValueNotifier<int>(0);
  GraphCanvasSize? _size;
  Size? _lastLayoutConstraints;

  Size? _currentSize;
  var _centered = false;
  var _relayoutInFlight = false;
  var _relayoutInvocationCount = 0;
  GraphLayoutTicket? _lastHandledLayoutSuccessTicket;
  var _cameraGated = false;
  var _zoomLiveWhileGated = false;
  Ticker? _ticker;
  TickerProvider? _tickerVsync;
  SceneLayoutAlgorithm? _requestedAlgorithm;
  Map<GraphNodeId, ScenePoint>? _transitionFrom;
  Map<GraphNodeId, ScenePoint>? _transitionTarget;
  Map<GraphNodeId, ScenePoint>? _layoutTransitionCapture;
  GraphLayoutTicket? _transitionLayoutTicket;
  int? _transitionTopologyRevision;
  bool _transitionsPaused = false;
  int _publicationGeneration = 0;
  GraphLayoutTicket? _pendingLayoutTicket;
  int? _pendingLayoutTopologyRevision;
  Map<GraphNodeId, ScenePoint>? _pendingLayoutPositions;
  Object? _viewOwner;
  VoidCallback? _gestureAbortCallback;
  VoidCallback? _gestureCameraSyncCallback;
  Offset? Function(Offset global)? _globalToViewportLocal;
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

  /// True while the gate also blocks wheel/trackpad zoom; a node drag keeps
  /// zoom live and re-projects its grab point instead.
  bool get isCameraZoomGated => _cameraGated && !_zoomLiveWhileGated;

  /// Stable node id resolver required for scene topology.
  GraphNodeIdResolver<N> get nodeIdOf => _nodeIdOf;

  /// Stable edge id resolver required for scene topology.
  GraphEdgeIdResolver<E> get edgeIdOf => _edgeIdOf;

  /// ID-keyed scene state owned by this controller.
  @visibleForTesting
  GraphSceneController<N, E> get scene => _scene;

  /// Increments on every camera transform change (pan/zoom/fit/jump).
  ValueListenable<int> get cameraRevision => _cameraRevision;

  /// Revision of the scene captured by [renderSnapshot].
  int get sceneRevision => _scene.sceneRevision;

  /// Current uniform camera scale; 1.0 before a view is attached.
  double get cameraScale =>
      _transformationController?.value.getMaxScaleOnAxis() ?? 1.0;

  /// Viewport size in logical pixels, or null before the first layout.
  Size? get viewportSize => _viewportPixelSize;

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

  /// Returns the displayed centre of [id], including any presentation override.
  Offset getPositionForId(GraphNodeId id) {
    final point = _scene.resolvePosition(id);
    if (point == null) {
      throw StateError('Node $id has no layout position yet');
    }
    return Offset(point.x, point.y);
  }

  /// Stable displayed position for a positioned node, disposed on removal.
  ValueListenable<Offset> positionListenableForId(GraphNodeId id) {
    if (_disposed) throw StateError('GraphController is disposed');
    return _nodePositions.putIfAbsent(
      id,
      () => _NodePositionListenable(getPositionForId(id)),
    );
  }

  /// Like [getPositionForId] but returns null when the node has no layout position.
  Offset? getPositionOrNullForId(GraphNodeId id) {
    final point = _scene.resolvePosition(id);
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

  /// Requests scene layout for the current topology and algorithm; ignored
  /// (returns null) while transitions are paused.
  GraphLayoutTicket? requestSceneLayout({
    Set<GraphPresentationToken> releaseOnTerminal = const {},
    SceneLayoutAlgorithm? algorithm,
  }) {
    final currentAlgorithm = algorithm ?? _currentAlgorithm;
    final currentSize = _currentSize;
    if (_transitionsPaused ||
        currentAlgorithm == null ||
        currentSize == null ||
        _nodes.isEmpty) {
      return null;
    }

    _requestedAlgorithm = currentAlgorithm;
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

  /// Cancels the layout job in flight, if any; it publishes nothing.
  bool cancelSceneLayout() => _scene.cancelActiveLayout();

  /// Active presentation drag token for [id], if any.
  GraphPresentationToken? activePresentationTokenForNode(GraphNodeId id) =>
      _scene.activePresentationTokenForNode(id);

  void _commitTopologyChange({
    required bool requestLayout,
    bool layoutOnTopologyChange = true,
  }) {
    _currentSize = _size?.resolve(nodeSizes: _nodes.map(_nodeSizeOf));
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
    final targetNodesById = {
      for (final node in targetNodes) _nodeIdOf(node): node,
    };
    final targetEdgesById = {
      for (final edge in targetEdges) _edgeIdOf(edge): edge,
    };

    final existingNodesById = <GraphNodeId, N>{};
    _nodes.removeWhere((node) {
      final id = _nodeIdOf(node);
      if (!targetNodesById.containsKey(id)) return true;
      existingNodesById.putIfAbsent(id, () => node);
      return false;
    });
    for (final entry in targetNodesById.entries) {
      final existing = existingNodesById[entry.key];
      if (existing == null) {
        _nodes.add(entry.value);
      } else if (existing != entry.value) {
        _nodes.remove(existing);
        _nodes.add(entry.value);
      }
    }

    final existingEdgesById = <GraphEdgeId, E>{};
    _edges.removeWhere((edge) {
      final id = _edgeIdOf(edge);
      if (!targetEdgesById.containsKey(id)) return true;
      existingEdgesById.putIfAbsent(id, () => edge);
      return false;
    });
    for (final entry in targetEdgesById.entries) {
      final existing = existingEdgesById[entry.key];
      if (existing == null) {
        _edges.add(entry.value);
      } else if (existing != entry.value) {
        _edges.remove(existing);
        _edges.add(entry.value);
      }
    }
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

  /// Starts a token-owned presentation drag for [id].
  GraphPresentationToken beginNodePresentationDragForId(
    GraphNodeId id,
    Offset position,
  ) {
    _freezeLayoutTransitionAtDisplay();
    return _scene.beginPresentation(
      id,
      ScenePoint(x: position.dx, y: position.dy),
      keepLayoutTransition: _transitionsPaused,
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

  /// Updates multiple presentation drags with one scene commit.
  int updateNodePresentationDrags(
    Map<GraphPresentationToken, Offset> updates,
  ) =>
      _scene.updatePresentations({
        for (final entry in updates.entries)
          entry.key: ScenePoint(x: entry.value.dx, y: entry.value.dy),
      });

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
  void jumpToPosition(
    Offset position, {
    bool resetScale = false,
    EdgeInsets viewportInsets = EdgeInsets.zero,
  }) {
    final controller = _transformationController;
    final pixel = _viewportPixelSize;
    if (controller == null || pixel == null) {
      return;
    }

    final oldScale = controller.value.getMaxScaleOnAxis();
    final matrixScale = resetScale ? 1.0 : oldScale;
    final usable = _usableViewportRect(pixel, viewportInsets);
    final centre = usable.center;

    controller.value = Matrix4.identity()
      ..translate(centre.dx, centre.dy)
      ..scale(matrixScale)
      ..translate(-position.dx, -position.dy);
    _syncActualViewportFromPixelSize();
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
  void fitToRect(
    Rect rect, {
    double padding = 48,
    EdgeInsets viewportInsets = EdgeInsets.zero,
    double? maxScale,
  }) {
    final transformation = _transformationController;
    final pixel = _viewportPixelSize;
    if (transformation == null || pixel == null) {
      return;
    }

    final padded = rect.inflate(padding);
    if (padded.width <= 0 || padded.height <= 0) {
      return;
    }

    final usable = _usableViewportRect(pixel, viewportInsets);
    final minBound = _boundaryMinScale();
    final maxBound =
        maxScale == null ? _maxScale : math.min(maxScale, _maxScale);
    final rawScale = math.min(
      usable.width / padded.width,
      usable.height / padded.height,
    );
    final scale = rawScale
        .clamp(math.min(minBound, maxBound), math.max(minBound, maxBound))
        .toDouble();

    final center = padded.center;
    final usableCentre = usable.center;
    transformation.value = Matrix4.identity()
      ..translate(usableCentre.dx, usableCentre.dy)
      ..scale(scale)
      ..translate(-center.dx, -center.dy);
    _syncActualViewportFromPixelSize();
  }

  Rect _usableViewportRect(Size pixel, EdgeInsets viewportInsets) {
    final usable = Rect.fromLTRB(
      viewportInsets.left,
      viewportInsets.top,
      pixel.width - viewportInsets.right,
      pixel.height - viewportInsets.bottom,
    );
    if (usable.width <= 0 || usable.height <= 0) {
      return Offset.zero & pixel;
    }
    return usable;
  }

  void _onCameraChanged() {
    _cameraRevision.value++;
    _syncGestureCamera();
  }

  void _syncGestureCamera() {
    if (_cameraGated) {
      _gestureCameraSyncCallback?.call();
    }
  }

  void _bindTransformationController(TransformationController controller) {
    if (identical(_transformationController, controller)) {
      return;
    }
    _transformationController?.removeListener(_onCameraChanged);
    _transformationController = controller;
    _transformationController?.addListener(_onCameraChanged);
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
    final snapshot = renderSnapshot;
    final changed = <_NodePositionListenable>[];
    _nodePositions.removeWhere((id, position) {
      if (!snapshot.topology.nodesById.containsKey(id)) {
        position.dispose();
        return true;
      }
      final point = snapshot.resolvePosition(id);
      if (point != null) {
        final next = Offset(point.x, point.y);
        if (position.value != next) {
          position._value = next;
          changed.add(position);
        }
      }
      return false;
    });
    // Commit every value before any listener observes this scene revision.
    for (final position in changed) {
      position._publish();
    }
    final generation = ++_publicationGeneration;
    final topologyRevision = _scene.topologyRevision;
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
      _pendingLayoutTicket = successTicket;
      _pendingLayoutTopologyRevision = topologyRevision;
      _pendingLayoutPositions = acceptedPositions;
    }

    void apply() {
      if (_disposed || generation != _publicationGeneration) {
        return;
      }
      // Paused transitions hold a new layout back, but other scene changes
      // (a node drag's presentation) must still reach the view.
      if (_transitionsPaused) {
        if (!isNewLayoutSuccess) _notify(heldWhilePaused: false);
        return;
      }
      if (topologyRevision != _scene.topologyRevision ||
          (successTicket != null &&
              successTicket != _scene.snapshot.layout?.ticket) ||
          !identical(outcome, _scene.layoutOutcome)) {
        return;
      }
      if (isNewLayoutSuccess && acceptedPositions != null) {
        _lastHandledLayoutSuccessTicket = successTicket;
        _pendingLayoutPositions = null;
        _handleAcceptedLayout(acceptedPositions);
      }
      if (shouldCenterAfterLayout && canLayout) {
        jumpToCenter();
        _centered = true;
      }
      notifyListeners();
    }

    // Request the frame before the deferred publication updates its consumers.
    _schedulerBindingOrNull()?.ensureVisualUpdate();
    scheduleMicrotask(apply);
  }

  void _handleAcceptedLayout(Map<GraphNodeId, ScenePoint> target) {
    final from = _layoutTransitionCapture ?? _captureDisplayedPositions();
    _layoutTransitionCapture = null;
    _startTransition(target, from);
  }

  /// Moves nodes from their displayed positions, tweening distances over 2 px.
  /// Nodes in [skip] keep their displayed positions.
  void animateTo(
    Map<GraphNodeId, ScenePoint> targets, {
    Set<GraphNodeId> skip = const {},
  }) {
    final from = _captureDisplayedPositions();
    final destinations = Map<GraphNodeId, ScenePoint>.from(from);
    for (final entry in targets.entries) {
      if (from.containsKey(entry.key) && !skip.contains(entry.key)) {
        destinations[entry.key] = entry.value;
      }
    }
    _scene.setLayoutPositions(destinations);
    _startTransition(destinations, from);
  }

  void _startTransition(
    Map<GraphNodeId, ScenePoint> target,
    Map<GraphNodeId, ScenePoint> from,
  ) {
    _ticker?.stop();
    final movingFrom = <GraphNodeId, ScenePoint>{};
    final movingTarget = <GraphNodeId, ScenePoint>{};
    if (_transitionDuration != Duration.zero && _ticker != null) {
      for (final entry in target.entries) {
        final start = from[entry.key] ?? _spawnScenePoint(entry.key);
        if (start == null) continue;
        final dx = entry.value.x - start.x;
        final dy = entry.value.y - start.y;
        if (dx * dx + dy * dy > 4) {
          movingFrom[entry.key] = start;
          movingTarget[entry.key] = entry.value;
        }
      }
    }
    _transitionFrom = movingFrom.isEmpty ? null : movingFrom;
    _transitionTarget = movingTarget.isEmpty ? null : movingTarget;
    _transitionLayoutTicket = _scene.snapshot.layout?.ticket;
    _transitionTopologyRevision = _scene.topologyRevision;
    _scene.setLayoutTransition(movingFrom.isEmpty ? null : movingFrom);
    if (movingFrom.isNotEmpty && !_transitionsPaused) _ticker?.start();
  }

  /// Freezes displayed geometry while retaining unfinished destinations.
  void pauseTransitions() {
    if (_transitionsPaused) return;
    _transitionsPaused = true;
    _publicationGeneration++;
    _ticker?.stop();
    if (_hasCurrentPendingLayout) {
      _scene.setLayoutTransition(_layoutTransitionCapture);
    } else if (_transitionTarget != null) {
      final displayed = _captureDisplayedPositions();
      _transitionFrom = {
        for (final id in _transitionTarget!.keys)
          if (displayed.containsKey(id)) id: displayed[id]!,
      };
    }
  }

  bool get _hasCurrentPendingLayout =>
      _pendingLayoutPositions != null &&
      _pendingLayoutTopologyRevision == _scene.topologyRevision &&
      _scene.layoutOutcome is GraphLayoutOutcomeSucceeded &&
      (_scene.layoutOutcome as GraphLayoutOutcomeSucceeded).ticket ==
          _pendingLayoutTicket;

  /// Continues toward retained destinations without counting paused time.
  void resumeTransitions() {
    if (!_transitionsPaused) return;
    _transitionsPaused = false;
    _publicationGeneration++;
    if (_hasCurrentPendingLayout) {
      final target = _pendingLayoutPositions!;
      _pendingLayoutPositions = null;
      _lastHandledLayoutSuccessTicket = _pendingLayoutTicket;
      _handleAcceptedLayout(target);
    } else if (_transitionFrom != null &&
        _transitionTarget != null &&
        _transitionTopologyRevision == _scene.topologyRevision &&
        _transitionLayoutTicket == _scene.snapshot.layout?.ticket) {
      _ticker?.start();
    } else {
      _transitionFrom = null;
      _transitionTarget = null;
      _pendingLayoutPositions = null;
    }
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
            size: SceneSize(
              width: _nodeSizeOf(node),
              height: _nodeSizeOf(node),
            ),
            simulationFixed: _nodeSimulationFixedOf(node),
          ),
      ],
      edges: [
        for (final edge in _edges)
          GraphSceneEdge(
            id: _edgeIdOf(edge),
            sourceId: _nodeIdOf(_edgeSourceOf(edge)),
            destinationId: _nodeIdOf(_edgeDestinationOf(edge)),
            payload: edge,
          ),
      ],
    );
  }

  void _freezeLayoutTransitionAtDisplay() {
    // A paused transition keeps its destinations for [resumeTransitions].
    if (_transitionsPaused) return;
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

  void _setCameraGated(bool gated, {bool zoomLive = false}) {
    final liveZoom = gated && zoomLive;
    if (_cameraGated == gated && _zoomLiveWhileGated == liveZoom) {
      return;
    }
    _cameraGated = gated;
    _zoomLiveWhileGated = liveZoom;
    _notify(heldWhilePaused: false);
  }

  /// Stops an in-progress layout transition without relayout.
  ///
  /// Used by the optional node-drag layer when a pointer capture begins.
  void stopLayoutAnimationForInteraction() {
    _freezeLayoutTransitionAtDisplay();
    notifyListeners();
  }

  /// Gates or releases camera pan/zoom for an active node-drag sequence.
  ///
  /// [zoomLive] keeps wheel/trackpad zoom enabled while gated; only the node
  /// drag, which re-projects its grab point, sets it.
  void setCameraInteractionGated(bool gated, {bool zoomLive = false}) =>
      _setCameraGated(gated, zoomLive: zoomLive);

  void _onTransitionTick(Duration elapsed) {
    if (_transitionsPaused) return;
    final from = _transitionFrom;
    final target = _transitionTarget;
    if (from == null || target == null) {
      _ticker?.stop();
      return;
    }

    final activeLayoutTicket = _scene.snapshot.layout?.ticket;
    if (_transitionTopologyRevision != _scene.topologyRevision ||
        (_transitionLayoutTicket != null &&
            activeLayoutTicket != _transitionLayoutTicket)) {
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
      final start =
          from[entry.key] ?? _spawnScenePoint(entry.key) ?? entry.value;
      interpolated[entry.key] = ScenePoint(
        x: start.x + (entry.value.x - start.x) * eased,
        y: start.y + (entry.value.y - start.y) * eased,
      );
    }
    _scene.setLayoutTransition(interpolated);

    // Keep pending layouts rebased on the geometry the animation displays.
    if (_relayoutInFlight) {
      _layoutTransitionCapture = _captureDisplayedPositions();
    }

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

  /// Wired by [NodeDragGesture]; not for app callers.
  ///
  /// [sync] runs whenever the camera moves while a node drag owns the
  /// pointer, so the drag can re-project the grab point.
  void registerGestureCameraSync(VoidCallback sync) {
    _gestureCameraSyncCallback = sync;
  }

  /// Wired by [NodeDragGesture]; not for app callers.
  void unregisterGestureCameraSync(VoidCallback sync) {
    if (identical(_gestureCameraSyncCallback, sync)) {
      _gestureCameraSyncCallback = null;
    }
  }

  /// Converts a global pointer position to canvas/scene space, or null before
  /// a view is attached.
  ///
  /// Uses the current camera, so it is valid right after a camera change,
  /// before the next frame repaints. Wired for [NodeDragGesture].
  Offset? globalToScene(Offset global) {
    final local = _globalToViewportLocal?.call(global);
    return local == null ? null : viewportLocalToScene(local);
  }

  void _abortActiveGestures() {
    _gestureAbortCallback?.call();
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
    _gestureCameraSyncCallback = null;
    _globalToViewportLocal = null;
    _setCameraGated(false);
    _lastLayoutConstraints = null;
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
      // The view origin may move with the resize, which only settles in
      // layout: re-project the grab point once it has.
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncGestureCamera());
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
    _transformationController?.removeListener(_onCameraChanged);
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
    final previousSize = _currentSize;
    final topologyRevision = _scene.topologyRevision;

    _lazyBuilding = lazyBuilding;
    _bindTransformationController(transformationController);
    _currentAlgorithm = algorithm;
    _size = size;
    _currentSize = _size?.resolve(nodeSizes: _nodes.map(_nodeSizeOf));
    _applyTopologyFromController();

    // A layout already requested with this algorithm, size and topology is not
    // repeated: repeating it would restart the transition it is running.
    final layoutCurrent = identical(algorithm, _requestedAlgorithm) &&
        previousSize == _currentSize &&
        topologyRevision == _scene.topologyRevision &&
        (_scene.layoutOutcome is GraphLayoutOutcomeRunning ||
            _scene.layoutOutcome is GraphLayoutOutcomeSucceeded);
    if (!layoutCurrent || _ticker == null || !identical(_tickerVsync, vsync)) {
      _ticker?.dispose();
      _tickerVsync = vsync;
      _ticker = vsync.createTicker(_onTransitionTick);
    }
    if (!layoutCurrent) _requestSceneLayout();
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
    _zoomLiveWhileGated = false;
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

  int? _deferredNotifyGeneration;
  var _disposed = false;

  @override
  void notifyListeners() => _notify(heldWhilePaused: true);

  /// Pausing transitions holds back scene publications, not the camera gate.
  void _notify({required bool heldWhilePaused}) {
    if (_disposed || (heldWhilePaused && _transitionsPaused)) return;
    final SchedulerBinding? binding = _schedulerBindingOrNull();
    if (binding != null) {
      final phase = binding.schedulerPhase;
      if (phase == SchedulerPhase.persistentCallbacks ||
          phase == SchedulerPhase.midFrameMicrotasks) {
        final generation = _publicationGeneration;
        if (_deferredNotifyGeneration == generation) {
          return;
        }
        _deferredNotifyGeneration = generation;
        final topologyRevision = _scene.topologyRevision;
        final layoutTicket = _scene.snapshot.layout?.ticket;
        final outcome = _scene.layoutOutcome;
        binding.addPostFrameCallback((_) {
          if (_deferredNotifyGeneration == generation) {
            _deferredNotifyGeneration = null;
          }
          if (_disposed ||
              (heldWhilePaused && _transitionsPaused) ||
              generation != _publicationGeneration ||
              topologyRevision != _scene.topologyRevision ||
              layoutTicket != _scene.snapshot.layout?.ticket ||
              !identical(outcome, _scene.layoutOutcome) ||
              !hasListeners) {
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
    _transformationController?.removeListener(_onCameraChanged);
    _scene.removeListener(_onSceneStateChanged);
    _scene.dispose();
    _ticker?.dispose();
    _ticker = null;
    _cameraRevision.dispose();
    for (final position in _nodePositions.values) {
      position.dispose();
    }
    _nodePositions.clear();
    super.dispose();
  }
}

class _NodePositionListenable extends ChangeNotifier
    implements ValueListenable<Offset> {
  _NodePositionListenable(this._value);

  Offset _value;

  @override
  Offset get value => _value;

  void _publish() => notifyListeners();
}
