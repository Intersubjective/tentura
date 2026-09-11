import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart';
import 'package:force_directed_graphview/src/widget/inherited_configuration.dart';

/// { @nodoc }
class NodesView extends StatelessWidget {
  /// { @nodoc }
  const NodesView({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final controller = InheritedConfiguration.controllerOf(context);
    final configuration = InheritedConfiguration.configurationOf(context);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        if (!controller.canLayout) {
          return const SizedBox();
        }

        final visibleNodes = controller.getVisibleNodes();
        final orderedNodes = controller
            .orderedNodes(
              visibleNodes,
              paintOrder: InheritedConfiguration.configurationOf(context)
                  .nodePaintOrder,
            )
            .toList(growable: false);

        return CustomMultiChildLayout(
          delegate: _NodesLayoutDelegate(
            nodes: orderedNodes,
            controller: controller,
          ),
          children: [
            for (final node in orderedNodes)
              LayoutId(
                id: node,
                child: RepaintBoundary(
                  child: configuration.nodeBuilder.build(context, node),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _NodesLayoutDelegate extends MultiChildLayoutDelegate {
  _NodesLayoutDelegate({
    required this.nodes,
    required this.controller,
  });

  final List<NodeBase> nodes;
  final GraphController controller;

  @override
  void performLayout(Size size) {
    for (final node in nodes) {
      final sizeSquare = Size.square(node.size);
      layoutChild(node, BoxConstraints.tight(sizeSquare));
      positionChild(
        node,
        controller.getPosition(node) - sizeSquare.center(Offset.zero),
      );
    }
  }

  @override
  bool shouldRelayout(covariant MultiChildLayoutDelegate oldDelegate) => true;
}
