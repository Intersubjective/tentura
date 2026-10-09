import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';

/// Optional node-drag and camera-gating layer for [GraphView].
class NodeDragGesture extends StatefulWidget {
  /// { @nodoc }
  const NodeDragGesture({
    required this.child,
    super.key,
  });

  /// { @nodoc }
  final Widget child;

  @override
  State<NodeDragGesture> createState() => _NodeDragGestureState();
}

class _NodeDragGestureState extends State<NodeDragGesture> {
  final _activePointers = <int>{};
  int? _canvasPointer;
  Offset? _canvasDownGlobal;
  Offset? _canvasDownViewport;
  int? _canvasButtons;
  Timer? _canvasLongPressTimer;
  var _canvasLongPressed = false;

  GraphNodeId? _pendingNodeId;
  GraphNodeId? _pendingTapNodeId;
  int? _pendingPointer;
  Offset? _pendingDownScene;
  Offset? _pendingLastScene;
  PointerDeviceKind? _pendingKind;
  var _pendingDragged = false;

  GraphNodeId? _capturedNodeId;
  GraphPresentationToken? _captureToken;
  int? _capturePointer;
  Offset _grabOffset = Offset.zero;
  // Pointer of the capture in global coordinates and the camera scale at which
  // [_grabOffset] was measured; the camera may move while the pointer stays.
  Offset? _grabGlobal;
  double _grabScale = 1;

  var _scaleBlocked = false;
  late GraphController<dynamic, dynamic> _controller;
  late GraphViewConfiguration _configuration;
  GraphController<dynamic, dynamic>? _registeredAbortController;
  late final VoidCallback _abortGestures = _abortActiveGestures;
  late final VoidCallback _syncCamera = _reprojectCapture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = InheritedConfiguration.controllerOf(context);
    _configuration = InheritedConfiguration.configurationOf(context);
    if (!identical(_registeredAbortController, nextController)) {
      _registeredAbortController
        ?..unregisterGestureLifecycleAbort(_abortGestures)
        ..unregisterGestureCameraSync(_syncCamera);
      _registeredAbortController = nextController;
      nextController
        ..registerGestureLifecycleAbort(_abortGestures)
        ..registerGestureCameraSync(_syncCamera);
    }
    _controller = nextController;
  }

  @override
  void dispose() {
    _cancelCanvasPress();
    _registeredAbortController
      ?..unregisterGestureLifecycleAbort(_abortGestures)
      ..unregisterGestureCameraSync(_syncCamera);
    _registeredAbortController = null;
    _releaseCapture(notifyCancel: true);
    super.dispose();
  }

  /// Keeps the dragged node under the stationary pointer after the camera or
  /// the view origin moved without the pointer.
  void _reprojectCapture() {
    final global = _grabGlobal;
    if (_capturedNodeId == null || global == null) {
      return;
    }
    final scene = _controller.globalToScene(global);
    if (scene == null) {
      return;
    }
    final scale = _controller.cameraScale;
    _grabOffset *= _grabScale / scale;
    _updateCapturedPosition(scene, global: global);
  }

  void _abortActiveGestures() {
    _cancelCanvasPress();
    _cancelPendingCapture();
    _releaseCapture(notifyCancel: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_configuration.nodePointerLayerEnabled) {
      return widget.child;
    }

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        _NodeDragPanGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_NodeDragPanGestureRecognizer>(
          () => _NodeDragPanGestureRecognizer(
            canStart: _canStartTouchNodeDrag,
            isOwning: _isOwningNode,
          ),
          (recognizer) {
            recognizer
              ..canStart = _canStartTouchNodeDrag
              ..isOwning = _isOwningNode
              ..onStart = _onTouchNodeDragStart;
          },
        ),
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: widget.child,
      ),
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);

    if (_capturedNodeId != null) {
      return;
    }

    if (_activePointers.length >= 2) {
      _cancelCanvasPress();
      if (_claimPendingNodeForOwner()) {
        return;
      }
      _cancelPendingCapture();
      _scaleBlocked = true;
      return;
    }

    if (_scaleBlocked) {
      return;
    }

    final pos = event.localPosition;
    final pass = _captureDragPassSnapshot();
    final canvasEnabled = _configuration.onCanvasTap != null ||
        _configuration.onCanvasSecondaryTap != null ||
        _configuration.onCanvasLongPress != null;
    if (canvasEnabled) {
      final nodeId = _hitTestTopmostNodeIdInSnapshot(
        pos,
        pass,
        draggableOnly: false,
      );
      final tapId =
          _configuration.nodeTapHitTester?.call(pos, pass.orderedNodeIds);
      if (nodeId == null && tapId == null) {
        _startCanvasPress(event);
        return;
      }
    }
    // A visible but non-draggable marker must not block a draggable node
    // underneath it. Taps still use the topmost node independently.
    final bodyId = _hitTestTopmostNodeIdInSnapshot(
      pos,
      pass,
      draggableOnly: true,
    );
    final tapId =
        _configuration.nodeTapHitTester?.call(pos, pass.orderedNodeIds) ??
            _hitTestTopmostNodeIdInSnapshot(pos, pass, draggableOnly: false);
    if (bodyId == null && tapId == null) {
      return;
    }

    _pendingNodeId = bodyId;
    _pendingTapNodeId = tapId;
    _pendingPointer = event.pointer;
    _pendingDownScene = event.localPosition;
    _pendingLastScene = event.localPosition;
    _pendingKind = event.kind;
    _pendingDragged = false;

    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton) {
      return;
    }
  }

  /// An additional touch must not turn a touch or stylus node press that has
  /// already moved past [kTouchSlop] into a camera pinch: the node pointer
  /// becomes the owner right away, and the recognizer then wins the extra
  /// pointers. A press that has not moved stays a pinch.
  bool _claimPendingNodeForOwner() {
    final nodeId = _pendingNodeId;
    final pointer = _pendingPointer;
    final down = _pendingDownScene;
    final last = _pendingLastScene;
    if (nodeId == null ||
        pointer == null ||
        down == null ||
        last == null ||
        _scaleBlocked ||
        (last - down).distance < kTouchSlop ||
        _pendingKind == PointerDeviceKind.mouse ||
        !_configuration.nodeDragEnabled ||
        _activePointers.length != 2) {
      return false;
    }
    final payload = _controller.nodePayloadForId(nodeId);
    if (payload == null || !_configuration.isNodeDraggable(payload)) {
      return false;
    }
    _captureNode(nodeId, pointer, down);
    if (_capturedNodeId == null) {
      return false;
    }
    _updateCapturedPosition(last);
    return true;
  }

  bool _isOwningNode() => _capturedNodeId != null;

  bool _canStartTouchNodeDrag(PointerDownEvent event) {
    // Keep every added touch in our already-won arena until the drag ends.
    // Camera gating rebuilds after a frame; allowing the viewer to recognize
    // a new pointer before then would still move the camera during a drag.
    if (_capturedNodeId != null) return true;
    if (!_configuration.nodeDragEnabled ||
        _scaleBlocked ||
        _activePointers.length >= 2) {
      return false;
    }
    final nodeId = _pendingNodeId;
    final payload =
        nodeId == null ? null : _controller.nodePayloadForId(nodeId);
    return payload != null && _configuration.isNodeDraggable(payload);
  }

  /// This recognizer joins the arena only for a draggable node. It therefore
  /// wins an actual node drag while an empty canvas remains available for pan.
  ///
  /// A mouse press on a draggable node also joins, only to keep the enclosing
  /// viewer from panning the camera before capture (its precise-pointer slop
  /// is far below [kTouchSlop]). The mouse capture itself still happens in
  /// [_onPointerMove] once the press crosses [kTouchSlop], so a slightly
  /// jittery click stays a tap and never becomes a drop.
  void _onTouchNodeDragStart(DragStartDetails details) {
    if (details.kind == PointerDeviceKind.mouse) {
      return;
    }
    final nodeId = _pendingNodeId;
    final pointer = _pendingPointer;
    final down = _pendingDownScene;
    if (nodeId == null ||
        pointer == null ||
        down == null ||
        _scaleBlocked ||
        _activePointers.length != 1) {
      return;
    }
    _captureNode(nodeId, pointer, down);
    _updateCapturedPosition(details.localPosition);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_canvasPointer == event.pointer &&
        (event.position - _canvasDownGlobal!).distance >= kTouchSlop) {
      _cancelCanvasPress();
    }
    if (_pendingNodeId == null &&
        _pendingTapNodeId != null &&
        event.pointer == _pendingPointer) {
      final down = _pendingDownScene;
      if (down != null && (event.localPosition - down).distance >= kTouchSlop) {
        _cancelPendingCapture();
        return;
      }
    }

    if (_capturedNodeId != null) {
      if (event.pointer != _capturePointer) {
        return;
      }
      // A pointer keeps the hit-test transforms of its press, which go stale
      // when the camera or the view origin moves mid-drag.
      _updateCapturedPosition(
        _controller.globalToScene(event.position) ?? event.localPosition,
        global: event.position,
      );
      return;
    }

    if (_pendingNodeId == null || event.pointer != _pendingPointer) {
      return;
    }
    _pendingLastScene = event.localPosition;

    if (_activePointers.length >= 2) {
      _cancelPendingCapture();
      _scaleBlocked = true;
      return;
    }

    final down = _pendingDownScene;
    if (down == null) {
      return;
    }

    if ((event.localPosition - down).distance < kTouchSlop) {
      return;
    }

    if (event.kind == PointerDeviceKind.mouse) {
      _pendingDragged = true;
      _captureNode(_pendingNodeId!, event.pointer, down);
      _updateCapturedPosition(event.localPosition);
      return;
    }

    // The touch-only pan recognizer captures this gesture once it crosses
    // slop. Do not cancel the pending node from this raw event first.
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);
    if (_canvasPointer == event.pointer) {
      final position = _controller.viewportLocalToScene(_canvasDownViewport!);
      final callback = _canvasLongPressed
          ? null
          : _canvasButtons == kSecondaryMouseButton
              ? _configuration.onCanvasSecondaryTap
              : _configuration.onCanvasTap;
      _cancelCanvasPress();
      callback?.call(position);
    }

    if (_capturedNodeId != null) {
      if (_activePointers.isEmpty) {
        _finishCapture();
      }
      return;
    }

    if (_pendingPointer == event.pointer) {
      final nodeId = _pendingTapNodeId ?? _pendingNodeId;
      final dragged = _pendingDragged;
      _cancelPendingCapture();
      if (nodeId != null &&
          !dragged &&
          _configuration.onNodeTap != null &&
          _capturedNodeId == null) {
        final payload = _controller.nodePayloadForId(nodeId);
        if (payload != null) {
          _configuration.onNodeTap!.call(payload);
        }
      }
    }

    if (_activePointers.isEmpty) {
      _scaleBlocked = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_canvasPointer == event.pointer) _cancelCanvasPress();
    _activePointers.remove(event.pointer);

    if (_capturedNodeId != null && event.pointer == _capturePointer) {
      _releaseCapture(notifyCancel: true);
    } else if (_pendingPointer == event.pointer) {
      _cancelPendingCapture();
    }

    if (_activePointers.isEmpty) {
      _scaleBlocked = false;
    }
  }

  void _startCanvasPress(PointerDownEvent event) {
    if (event.buttons != kPrimaryButton &&
        event.buttons != kSecondaryMouseButton) {
      return;
    }
    _canvasPointer = event.pointer;
    _canvasDownGlobal = event.position;
    // This listener is inside InteractiveViewer's transformed child, so its
    // local coordinates are already scene coordinates. Store viewport-local
    // coordinates for the controller's conversion at callback dispatch.
    _canvasDownViewport = _controller.sceneToViewportLocal(event.localPosition);
    _canvasButtons = event.buttons;
    _canvasLongPressed = false;
    if (event.buttons == kPrimaryButton) {
      _canvasLongPressTimer = Timer(kLongPressTimeout, () {
        _canvasLongPressed = true;
        final position = _controller.viewportLocalToScene(_canvasDownViewport!);
        _configuration.onCanvasLongPress?.call(position);
      });
    }
  }

  void _cancelCanvasPress() {
    _canvasLongPressTimer?.cancel();
    _canvasLongPressTimer = null;
    _canvasPointer = null;
    _canvasDownGlobal = null;
    _canvasDownViewport = null;
    _canvasButtons = null;
    _canvasLongPressed = false;
  }

  _DragPassSnapshot _captureDragPassSnapshot() {
    final snapshot = _controller.renderSnapshot;
    return _DragPassSnapshot(
      snapshot: snapshot,
      orderedNodeIds: _controller.orderedRenderNodeIds(
        snapshot,
        configuredPaintOrder: _configuration.nodePaintOrder,
      ),
    );
  }

  GraphNodeId? _hitTestTopmostNodeIdInSnapshot(
    Offset scenePosition,
    _DragPassSnapshot pass, {
    required bool draggableOnly,
  }) {
    if (!_controller.canLayout) {
      return null;
    }

    for (final id in pass.orderedNodeIds.reversed) {
      final sceneNode = pass.snapshot.topology.nodesById[id];
      final point = pass.snapshot.resolvePosition(id);
      if (sceneNode == null || point == null) {
        continue;
      }
      final payload = sceneNode.payload;
      if (draggableOnly && !_configuration.isNodeDraggable(payload)) {
        continue;
      }
      final centre = Offset(point.x, point.y);
      final rect = Rect.fromCenter(
        center: centre,
        width: sceneNode.size.width,
        height: sceneNode.size.height,
      );
      if (rect.contains(scenePosition)) {
        return id;
      }
    }
    return null;
  }

  void _captureNode(GraphNodeId nodeId, int pointer, Offset downScene) {
    _pendingNodeId = null;
    _pendingPointer = null;
    _pendingDownScene = null;
    _pendingLastScene = null;
    _pendingKind = null;

    final pass = _captureDragPassSnapshot();
    final point = pass.snapshot.resolvePosition(nodeId);
    if (point == null) {
      return;
    }
    final centre = Offset(point.x, point.y);

    _capturedNodeId = nodeId;
    _capturePointer = pointer;
    _grabOffset = downScene - centre;
    _grabScale = _controller.cameraScale;
    _controller.setCameraInteractionGated(true, zoomLive: true);

    try {
      final payload = _controller.nodePayloadForId(nodeId);
      if (payload != null) {
        _configuration.onNodeDragStart?.call(payload, centre);
      }
      // After the start callback, so an app that pauses transitions there
      // keeps their destinations.
      _controller.stopLayoutAnimationForInteraction();
    } catch (_) {
      _releaseCapture(notifyCancel: true);
      rethrow;
    }
  }

  void _updateCapturedPosition(Offset scenePosition, {Offset? global}) {
    final nodeId = _capturedNodeId;
    if (nodeId == null) {
      return;
    }

    // The painted transform lags a camera change, so a re-projection passes
    // the pointer's known global position instead of deriving it.
    final box = context.findRenderObject();
    if (global != null) {
      _grabGlobal = global;
    } else if (box is RenderBox && box.hasSize) {
      _grabGlobal = box.localToGlobal(scenePosition);
    }
    _grabScale = _controller.cameraScale;
    var centre = scenePosition - _grabOffset;
    final payload = _controller.nodePayloadForId(nodeId);
    if (payload == null) {
      return;
    }
    final transform = _configuration.transformNodeDragPosition;
    if (transform != null) {
      centre = transform(payload, centre);
    }

    try {
      final token = _captureToken;
      if (token == null) {
        _captureToken =
            _controller.beginNodePresentationDragForId(nodeId, centre);
      } else {
        _controller.updateNodePresentationDrag(token, centre);
      }
      _configuration.onNodeDragUpdate?.call(payload, centre);
    } catch (_) {
      _releaseCapture(notifyCancel: true);
      rethrow;
    }
  }

  void _finishCapture() {
    final nodeId = _capturedNodeId;
    if (nodeId == null) {
      return;
    }

    final payload = _controller.nodePayloadForId(nodeId);
    final position = _controller.getPositionOrNullForId(nodeId);

    _capturedNodeId = null;
    _captureToken = null;
    _capturePointer = null;
    _grabOffset = Offset.zero;
    _grabGlobal = null;

    try {
      if (payload != null && position != null) {
        _configuration.onNodeDragEnd?.call(payload, position);
      }
    } finally {
      _controller.setCameraInteractionGated(false);
    }
  }

  void _releaseCapture({
    required bool notifyCancel,
  }) {
    final nodeId = _capturedNodeId;
    _capturedNodeId = null;
    _captureToken = null;
    _capturePointer = null;
    _grabOffset = Offset.zero;
    _grabGlobal = null;

    if (nodeId == null) {
      return;
    }

    try {
      if (notifyCancel) {
        final payload = _controller.nodePayloadForId(nodeId);
        if (payload != null) {
          _controller.clearPresentationForNodeId(nodeId);
          _configuration.onNodeDragCancel?.call(payload);
        }
      }
    } finally {
      _controller.setCameraInteractionGated(false);
    }
  }

  void _cancelPendingCapture() {
    _pendingNodeId = null;
    _pendingTapNodeId = null;
    _pendingPointer = null;
    _pendingDownScene = null;
    _pendingLastScene = null;
    _pendingKind = null;
    _pendingDragged = false;
  }
}

final class _DragPassSnapshot {
  const _DragPassSnapshot({
    required this.snapshot,
    required this.orderedNodeIds,
  });

  final GraphSceneSnapshot<Object?, Object?> snapshot;
  final List<GraphNodeId> orderedNodeIds;
}

final class _NodeDragPanGestureRecognizer extends PanGestureRecognizer {
  _NodeDragPanGestureRecognizer({
    required this.canStart,
    required this.isOwning,
  })
      : super(
          supportedDevices: const {
            PointerDeviceKind.touch,
            PointerDeviceKind.stylus,
            PointerDeviceKind.mouse,
          },
        );

  bool Function(PointerDownEvent event) canStart;

  /// Whether a node drag already owns the gesture sequence.
  bool Function() isOwning;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    // The gated viewer only rebuilds a frame after capture, and a captured
    // drag may not have crossed pan slop yet, so win every pointer here or the
    // viewer's scale recognizer takes them.
    if (isOwning()) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event is! PointerDownEvent) return false;
    if (!canStart(event)) {
      // A second finger must release a pending node drag to the enclosing
      // scale recognizer. Refusing only the new pointer leaves the first
      // pointer in the arena and can still steal the pinch as a node pan.
      resolve(GestureDisposition.rejected);
      return false;
    }
    return super.isPointerAllowed(event);
  }
}
