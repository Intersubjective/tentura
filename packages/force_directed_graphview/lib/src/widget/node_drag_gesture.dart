import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/configuration.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/graph_presentation_token.dart';
import 'package:force_directed_graphview/src/scene/scene_snapshot.dart';
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
  static const _longPressDuration = Duration(milliseconds: 500);

  final _activePointers = <int>{};

  GraphNodeId? _pendingNodeId;
  int? _pendingPointer;
  Offset? _pendingDownScene;
  var _pendingDragged = false;
  Timer? _longPressTimer;

  GraphNodeId? _capturedNodeId;
  GraphPresentationToken? _captureToken;
  int? _capturePointer;
  Offset _grabOffset = Offset.zero;

  var _scaleBlocked = false;
  late GraphController _controller;
  late GraphViewConfiguration _configuration;
  GraphController? _registeredAbortController;
  late final VoidCallback _abortGestures = _abortActiveGestures;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextController = InheritedConfiguration.controllerOf(context);
    _configuration = InheritedConfiguration.configurationOf(context);
    if (!identical(_registeredAbortController, nextController)) {
      _registeredAbortController?.unregisterGestureLifecycleAbort(_abortGestures);
      _registeredAbortController = nextController;
      nextController.registerGestureLifecycleAbort(_abortGestures);
    }
    _controller = nextController;
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    _registeredAbortController?.unregisterGestureLifecycleAbort(_abortGestures);
    _registeredAbortController = null;
    _releaseCapture(notifyCancel: true);
    super.dispose();
  }

  void _abortActiveGestures() {
    _cancelPendingCapture();
    _releaseCapture(notifyCancel: true);
  }

  @override
  Widget build(BuildContext context) {
    if (!_configuration.nodePointerLayerEnabled) {
      return widget.child;
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onPointerDown,
      onPointerMove: _onPointerMove,
      onPointerUp: _onPointerUp,
      onPointerCancel: _onPointerCancel,
      child: widget.child,
    );
  }

  void _onPointerDown(PointerDownEvent event) {
    _activePointers.add(event.pointer);

    if (_capturedNodeId != null) {
      return;
    }

    if (_activePointers.length >= 2) {
      _cancelPendingCapture();
      _scaleBlocked = true;
      return;
    }

    if (_scaleBlocked) {
      return;
    }

    final nodeId = _configuration.onNodeTap != null
        ? _hitTestTopmostVisibleNodeId(event.localPosition)
        : _hitTestTopmostNodeId(event.localPosition);
    if (nodeId == null) {
      return;
    }

    _pendingNodeId = nodeId;
    _pendingPointer = event.pointer;
    _pendingDownScene = event.localPosition;
    _pendingDragged = false;

    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton) {
      return;
    }

    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      if (_pendingPointer == event.pointer && _pendingNodeId == nodeId) {
        _captureNode(nodeId, event.pointer, event.localPosition);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_capturedNodeId != null) {
      if (event.pointer != _capturePointer) {
        return;
      }
      _updateCapturedPosition(event.localPosition);
      return;
    }

    if (_pendingNodeId == null || event.pointer != _pendingPointer) {
      return;
    }

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

    _pendingDragged = true;

    if (event.kind == PointerDeviceKind.mouse) {
      _captureNode(_pendingNodeId!, event.pointer, down);
      _updateCapturedPosition(event.localPosition);
      return;
    }

    _cancelPendingCapture();
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);

    if (_capturedNodeId != null) {
      if (_activePointers.isEmpty) {
        _finishCapture();
      }
      return;
    }

    if (_pendingPointer == event.pointer) {
      final nodeId = _pendingNodeId;
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

  GraphNodeId? _hitTestTopmostNodeId(Offset scenePosition) {
    return _hitTestTopmostNodeIdInSnapshot(
      scenePosition,
      draggableOnly: true,
    );
  }

  GraphNodeId? _hitTestTopmostVisibleNodeId(Offset scenePosition) {
    return _hitTestTopmostNodeIdInSnapshot(
      scenePosition,
      draggableOnly: false,
    );
  }

  GraphNodeId? _hitTestTopmostNodeIdInSnapshot(
    Offset scenePosition, {
    required bool draggableOnly,
  }) {
    if (!_controller.canLayout) {
      return null;
    }

    final pass = _captureDragPassSnapshot();

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
    _longPressTimer?.cancel();
    _pendingNodeId = null;
    _pendingPointer = null;
    _pendingDownScene = null;

    _controller.stopLayoutAnimationForInteraction();
    final pass = _captureDragPassSnapshot();
    final point = pass.snapshot.resolvePosition(nodeId);
    if (point == null) {
      return;
    }
    final centre = Offset(point.x, point.y);

    _capturedNodeId = nodeId;
    _capturePointer = pointer;
    _grabOffset = downScene - centre;
    _controller.setCameraInteractionGated(true);

    try {
      final payload = _controller.nodePayloadForId(nodeId);
      if (payload != null) {
        _configuration.onNodeDragStart?.call(payload, centre);
      }
    } catch (_) {
      _releaseCapture(notifyCancel: true);
      rethrow;
    }
  }

  void _updateCapturedPosition(Offset scenePosition) {
    final nodeId = _capturedNodeId;
    if (nodeId == null) {
      return;
    }

    final centre = scenePosition - _grabOffset;
    final payload = _controller.nodePayloadForId(nodeId);
    if (payload == null) {
      return;
    }

    try {
      final token = _captureToken;
      if (token == null) {
        _captureToken = _controller.beginNodePresentationDragForId(nodeId, centre);
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
    _longPressTimer?.cancel();
    _pendingNodeId = null;
    _pendingPointer = null;
    _pendingDownScene = null;
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
