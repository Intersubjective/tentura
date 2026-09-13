import 'package:flutter/widgets.dart';
import 'package:force_directed_graphview/src/label_builder/label_builder.dart';
/// Label builder that places the label below the node.
final class BottomLabelBuilder<N> implements LabelBuilder<N> {
  /// { @nodoc }
  BottomLabelBuilder({
    required this.builder,
    required this.labelSize,
  });

  /// Extracts the label widget from the node.
  final Widget Function(BuildContext context, N node) builder;

  /// The size of the area available to the label.
  final Size labelSize;

  @override
  void performLayout(
    Size size,
    N node,
    double nodeSize,
    Offset nodePosition,
    Size Function(BoxConstraints constraints) layoutChild,
    void Function(Offset offset) positionChild,
  ) {
    final widthDelta = nodeSize - labelSize.width;

    layoutChild(BoxConstraints.tight(labelSize));

    positionChild(
      nodePosition +
          Offset(-nodeSize / 2, nodeSize / 2) +
          Offset(widthDelta / 2, 0),
    );
  }

  @override
  Widget build(BuildContext context, N node) {
    return builder(context, node);
  }
}
