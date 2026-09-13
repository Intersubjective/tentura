import 'dart:ui';

import 'package:force_directed_graphview/src/layout_algorithm/graph_layout_algorithm.dart';
import 'package:force_directed_graphview/src/layout_algorithm/scene_layout_algorithm.dart';
import 'package:force_directed_graphview/src/model/edge.dart';
import 'package:force_directed_graphview/src/model/graph_layout.dart';
import 'package:force_directed_graphview/src/model/node.dart';
import 'package:meta/meta.dart';

/// [GraphLayoutAlgorithm] handle for a native [SceneLayoutAlgorithm].
///
/// Widget configuration and [GraphController.useLayoutAlgorithm] still use the
/// legacy type; the controller unwraps [delegate] for scene layout requests.
@immutable
final class BoundSceneLayoutAlgorithm implements GraphLayoutAlgorithm {
  const BoundSceneLayoutAlgorithm(this.delegate);

  final SceneLayoutAlgorithm delegate;

  @override
  Stream<GraphLayout> layout({
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) {
    throw UnsupportedError(
      'BoundSceneLayoutAlgorithm is invoked through GraphSceneController.requestLayout',
    );
  }

  @override
  Stream<GraphLayout> relayout({
    required GraphLayout existingLayout,
    required Set<NodeBase> nodes,
    required Set<EdgeBase> edges,
    required Size size,
  }) =>
      layout(nodes: nodes, edges: edges, size: size);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BoundSceneLayoutAlgorithm && delegate == other.delegate;

  @override
  int get hashCode => delegate.hashCode;
}
