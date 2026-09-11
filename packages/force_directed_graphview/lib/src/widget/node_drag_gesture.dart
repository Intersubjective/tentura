import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/configuration.dart';
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

  NodeBase? _pendingNode;
  int? _pendingPointer;
  Offset? _pendingDownScene;
  Timer? _longPressTimer;

  NodeBase? _capturedNode;
  int? _capturePointer;
  Offset _grabOffset = Offset.zero;

  var _scaleBlocked = false;
  late GraphController _controller;
  late GraphViewConfiguration _configuration;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller = InheritedConfiguration.controllerOf(context);
    _configuration = InheritedConfiguration.configurationOf(context);
  }

  @override
  void dispose() {
    _longPressTimer?.cancel();
    final node = _capturedNode;
    _capturedNode = null;
    _capturePointer = null;
    if (node != null) {
      _controller.setCameraInteractionGated(false);
      _controller.clearPresentationPosition(node);
      _configuration.onNodeDragCancel?.call(node);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_configuration.nodeDragEnabled) {
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

    if (_capturedNode != null) {
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

    final node = _hitTestTopmostNode(event.localPosition);
    if (node == null) {
      return;
    }

    _pendingNode = node;
    _pendingPointer = event.pointer;
    _pendingDownScene = event.localPosition;

    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons == kPrimaryMouseButton) {
      return;
    }

    _longPressTimer?.cancel();
    _longPressTimer = Timer(_longPressDuration, () {
      if (_pendingPointer == event.pointer && _pendingNode == node) {
        _captureNode(node, event.pointer, event.localPosition);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_capturedNode != null) {
      if (event.pointer != _capturePointer) {
        return;
      }
      _updateCapturedPosition(event.localPosition);
      return;
    }

    if (_pendingNode == null || event.pointer != _pendingPointer) {
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

    if (event.kind == PointerDeviceKind.mouse) {
      _captureNode(_pendingNode!, event.pointer, down);
      _updateCapturedPosition(event.localPosition);
      return;
    }

    _cancelPendingCapture();
  }

  void _onPointerUp(PointerUpEvent event) {
    _activePointers.remove(event.pointer);

    if (_capturedNode != null) {
      if (_activePointers.isEmpty) {
        _finishCapture();
      }
      return;
    }

    if (_pendingPointer == event.pointer) {
      _cancelPendingCapture();
    }

    if (_activePointers.isEmpty) {
      _scaleBlocked = false;
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    _activePointers.remove(event.pointer);

    if (_capturedNode != null && event.pointer == _capturePointer) {
      _releaseCapture(notifyCancel: true);
    } else if (_pendingPointer == event.pointer) {
      _cancelPendingCapture();
    }

    if (_activePointers.isEmpty) {
      _scaleBlocked = false;
    }
  }

  NodeBase? _hitTestTopmostNode(Offset scenePosition) {
    if (!_controller.canLayout) {
      return null;
    }

    final visibleNodes = _controller.getVisibleNodes();
    final ordered = _controller
        .orderedNodes(
          visibleNodes,
          paintOrder: _configuration.nodePaintOrder,
        )
        .toList(growable: false);

    for (final node in ordered.reversed) {
      if (!_configuration.isNodeDraggable(node)) {
        continue;
      }
      final position = _controller.getPosition(node);
      final rect = Rect.fromCenter(
        center: position,
        width: node.size,
        height: node.size,
      );
      if (rect.contains(scenePosition)) {
        return node;
      }
    }
    return null;
  }

  void _captureNode(NodeBase node, int pointer, Offset downScene) {
    _longPressTimer?.cancel();
    _pendingNode = null;
    _pendingPointer = null;
    _pendingDownScene = null;

    _controller.stopLayoutAnimationForInteraction();
    final centre = _controller.getPosition(node);

    _capturedNode = node;
    _capturePointer = pointer;
    _grabOffset = downScene - centre;
    _controller.setCameraInteractionGated(true);

    _configuration.onNodeDragStart?.call(node, centre);
  }

  void _updateCapturedPosition(Offset scenePosition) {
    final node = _capturedNode;
    if (node == null) {
      return;
    }

    final centre = scenePosition - _grabOffset;
    _controller.setNodePresentationPosition(node, centre);
    _configuration.onNodeDragUpdate?.call(node, centre);
  }

  void _finishCapture() {
    final node = _capturedNode;
    if (node == null) {
      return;
    }

    final position = _controller.getPosition(node);
    _configuration.onNodeDragEnd?.call(node, position);
    _capturedNode = null;
    _capturePointer = null;
    _grabOffset = Offset.zero;
    _controller.setCameraInteractionGated(false);
  }

  void _releaseCapture({
    required bool notifyCancel,
  }) {
    final node = _capturedNode;
    _capturedNode = null;
    _capturePointer = null;
    _grabOffset = Offset.zero;
    _controller.setCameraInteractionGated(false);

    if (node == null) {
      return;
    }

    if (notifyCancel) {
      _controller.clearPresentationPosition(node);
      _configuration.onNodeDragCancel?.call(node);
    }
  }

  void _cancelPendingCapture() {
    _longPressTimer?.cancel();
    _pendingNode = null;
    _pendingPointer = null;
    _pendingDownScene = null;
  }
}
