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
    final scope = GraphSceneRenderScope.of(context);

    return CustomMultiChildLayout(
      delegate: _NodesLayoutDelegate(
        snapshot: scope.snapshot,
        orderedNodeIds: scope.orderedNodeIds,
      ),
      children: [
        for (final id in scope.orderedNodeIds)
          LayoutId(
            id: id,
            child: RepaintBoundary(
              key: ValueKey<String>(id),
              child: configuration.nodeBuilder.build(
                context,
                scope.snapshot.topology.nodesById[id]!.payload,
              ),
            ),
          ),
      ],
    );
  }
}

class _NodesLayoutDelegate extends MultiChildLayoutDelegate {
  _NodesLayoutDelegate({
    required this.snapshot,
    required this.orderedNodeIds,
  });

  final GraphSceneSnapshot<NodeBase, EdgeBase> snapshot;
  final List<GraphNodeId> orderedNodeIds;

  @override
  void performLayout(Size size) {
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
      snapshot != oldDelegate.snapshot ||
      orderedNodeIds != oldDelegate.orderedNodeIds;
}
