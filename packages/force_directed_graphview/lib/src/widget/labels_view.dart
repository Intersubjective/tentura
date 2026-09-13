import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/scene/graph_ids.dart';
import 'package:force_directed_graphview/src/scene/scene_snapshot.dart';
import 'package:force_directed_graphview/src/widget/graph_layout_view.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';

/// { @nodoc }
class LabelsView extends StatelessWidget {
  /// { @nodoc }
  const LabelsView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final configuration = InheritedConfiguration.configurationOf(context);
    final labelBuilder = configuration.labelBuilder;

    if (labelBuilder == null) {
      return const SizedBox();
    }

    final scope = GraphSceneRenderScope.of(context);

    final idToLabel = {
      for (final id in scope.orderedNodeIds)
        id: labelBuilder.build(
          context,
          scope.snapshot.topology.nodesById[id]!.payload,
        ),
    };

    return CustomMultiChildLayout(
      delegate: _LabelsLayoutDelegate(
        snapshot: scope.snapshot,
        labels: idToLabel,
        labelBuilder: labelBuilder,
      ),
      children: [
        for (final entry in idToLabel.entries)
          LayoutId(
            id: entry.key,
            child: RepaintBoundary(
              key: ValueKey<String>('label-${entry.key}'),
              child: entry.value,
            ),
          ),
      ],
    );
  }
}

class _LabelsLayoutDelegate extends MultiChildLayoutDelegate {
  _LabelsLayoutDelegate({
    required this.snapshot,
    required this.labels,
    required this.labelBuilder,
  });

  final GraphSceneSnapshot<Object?, Object?> snapshot;
  final Map<GraphNodeId, Widget> labels;
  final LabelBuilder labelBuilder;

  @override
  void performLayout(Size size) {
    for (final entry in labels.entries) {
      final id = entry.key;
      final node = snapshot.topology.nodesById[id]!.payload;
      final point = snapshot.resolvePosition(id);
      if (point == null) {
        continue;
      }

      labelBuilder.performLayout(
        size,
        node,
        snapshot.topology.nodesById[id]!.size.width,
        Offset(point.x, point.y),
        (constraints) => layoutChild(id, constraints),
        (offset) => positionChild(id, offset),
      );
    }
  }

  @override
  bool shouldRelayout(covariant _LabelsLayoutDelegate oldDelegate) =>
      snapshot != oldDelegate.snapshot || labels != oldDelegate.labels;
}
