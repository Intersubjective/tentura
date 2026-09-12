import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/scene_snapshot.dart';
import 'package:force_directed_graphview/src/widget/edges_view.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';
import 'package:force_directed_graphview/src/widget/labels_view.dart';
import 'package:force_directed_graphview/src/widget/nodes_view.dart';

/// One immutable scene capture shared by paint and hit testing for a frame.
class GraphSceneRenderScope extends InheritedWidget {
  /// { @nodoc }
  const GraphSceneRenderScope({
    required this.snapshot,
    required this.orderedNodeIds,
    required super.child,
    super.key,
  });

  /// Scene revision captured once per layout pass.
  final GraphSceneSnapshot<NodeBase, EdgeBase> snapshot;

  /// Visible node ids in paint/hit order (later ids are on top).
  final List<GraphNodeId> orderedNodeIds;

  /// { @nodoc }
  static GraphSceneRenderScope of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GraphSceneRenderScope>();
    assert(scope != null, 'GraphSceneRenderScope not found');
    return scope!;
  }

  @override
  bool updateShouldNotify(GraphSceneRenderScope oldWidget) =>
      snapshot != oldWidget.snapshot ||
      orderedNodeIds != oldWidget.orderedNodeIds;
}

/// { @nodoc }
class GraphLayoutView extends StatelessWidget {
  /// { @nodoc }
  const GraphLayoutView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final configuration = InheritedConfiguration.configurationOf(context);
    final controller = InheritedConfiguration.controllerOf(context);
    final backgroundBuilder = configuration.canvasBackgroundBuilder;
    final builder = configuration.builder;

    Widget result = AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.canLayout) {
          return const SizedBox.shrink();
        }

        final snapshot = controller.renderSnapshot;
        final orderedNodeIds = controller.orderedRenderNodeIds(
          snapshot,
          legacyPaintOrder: configuration.nodePaintOrder,
        );

        return GraphSceneRenderScope(
          snapshot: snapshot,
          orderedNodeIds: orderedNodeIds,
          child: SizedBox.fromSize(
            size: controller.canvasSize,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (backgroundBuilder != null)
                  RepaintBoundary(
                    child: backgroundBuilder(context),
                  ),
                const EdgesView(),
                const LabelsView(),
                const NodesView(),
              ],
            ),
          ),
        );
      },
    );

    if (builder != null) {
      result = builder(context, result);
    }

    return result;
  }
}
