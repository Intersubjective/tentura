import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/scene_snapshot.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';

/// { @nodoc }
class NodesView extends StatelessWidget {
  /// { @nodoc }
  const NodesView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final configuration = InheritedConfiguration.configurationOf(context);
    final scope = GraphSceneRenderScope.membershipOf(context);

    return _NodesLayout(
      children: {
        for (final id in scope.orderedNodeIds)
          id: LayoutId(
            key: ValueKey<String>(id),
            id: id,
            child: _NodeIsolation(
              key: ValueKey<String>(id),
              id: id,
              child: configuration.nodeBuilder.build(
                context,
                scope.snapshot.topology.nodesById[id]!.payload,
              ),
            ),
          ),
      },
    );
  }
}

/// Gives a node its own repaint boundary only while it is being moved
/// (dragged or animating towards a new layout), so resting nodes paint into
/// the shared scene layer instead of each adding a picture layer.
class _NodeIsolation extends StatefulWidget {
  const _NodeIsolation({
    required this.id,
    required this.child,
    super.key,
  });

  final GraphNodeId id;
  final Widget child;

  @override
  State<_NodeIsolation> createState() => _NodeIsolationState();
}

class _NodeIsolationState extends State<_NodeIsolation> {
  /// Keeps the node content's state when the boundary is added or removed.
  final _contentKey = GlobalKey();

  GraphController<dynamic, dynamic>? _controller;
  bool _moving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final controller = InheritedConfiguration.controllerOf(context);
    if (!identical(controller, _controller)) {
      _controller?.removeListener(_onSceneChanged);
      _controller = controller..addListener(_onSceneChanged);
    }
    _moving = _isMoving();
  }

  @override
  void dispose() {
    _controller?.removeListener(_onSceneChanged);
    super.dispose();
  }

  bool _isMoving() {
    final snapshot = _controller!.renderSnapshot;
    return snapshot.presentation.overrides.containsKey(widget.id) ||
        (snapshot.transition?.positions.containsKey(widget.id) ?? false);
  }

  void _onSceneChanged() {
    final moving = _isMoving();
    if (moving != _moving) {
      setState(() => _moving = moving);
    }
  }

  @override
  Widget build(BuildContext context) {
    final content = KeyedSubtree(key: _contentKey, child: widget.child);
    return _moving ? RepaintBoundary(child: content) : content;
  }
}

class _NodesLayout extends StatelessWidget {
  const _NodesLayout({required this.children});

  final Map<GraphNodeId, Widget> children;

  @override
  Widget build(BuildContext context) {
    final scope = GraphSceneRenderScope.paintOrderOf(context);
    final controller = InheritedConfiguration.controllerOf(context);
    return CustomMultiChildLayout(
      delegate: _NodesLayoutDelegate(
        controller: controller,
        orderedNodeIds: scope.orderedNodeIds,
      ),
      children: [
        for (final id in scope.orderedNodeIds) children[id]!,
      ],
    );
  }
}

class _NodesLayoutDelegate extends MultiChildLayoutDelegate {
  _NodesLayoutDelegate({
    required this.controller,
    required this.orderedNodeIds,
  }) : super(relayout: controller);

  /// Positions are read at layout time, so a position-only scene change
  /// relays out without rebuilding this widget.
  final GraphController<dynamic, dynamic> controller;
  final List<GraphNodeId> orderedNodeIds;

  @override
  void performLayout(Size size) {
    final snapshot = controller.renderSnapshot;
    for (final id in orderedNodeIds) {
      final sceneNode = snapshot.topology.nodesById[id];
      final point = snapshot.resolvePosition(id);
      if (sceneNode == null || point == null) {
        continue;
      }
      final sizeSquare = Size.square(sceneNode.size.width);
      layoutChild(id, BoxConstraints.tight(sizeSquare));
      positionChild(
        id,
        Offset(point.x, point.y) - sizeSquare.center(Offset.zero),
      );
    }
  }

  @override
  bool shouldRelayout(covariant _NodesLayoutDelegate oldDelegate) =>
      controller != oldDelegate.controller ||
      orderedNodeIds != oldDelegate.orderedNodeIds;
}
