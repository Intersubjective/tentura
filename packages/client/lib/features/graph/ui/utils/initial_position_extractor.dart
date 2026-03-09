import 'dart:math' show Random;
import 'dart:ui' show Offset, Size;
import 'package:force_directed_graphview/force_directed_graphview.dart'
    show FruchtermanReingoldAlgorithm, NodeBase;

import '../../domain/entity/node_details.dart';

Offset initialPositionExtractor(NodeBase node, Size canvasSize) {
  if (node is NodeDetails && node.positionHint != null) {
    return _calculatePositionWithHint(node, canvasSize);
  }
  return FruchtermanReingoldAlgorithm.defaultInitialPositionExtractor(
    node,
    canvasSize,
  );
}

Offset _calculatePositionWithHint(NodeDetails node, Size canvasSize) {
  return canvasSize.center(Offset.zero) + Offset(
      (_random.nextDouble() * 2 - 1) * (_optimalDistance * 0.01),
      -(verticalShift + _optimalDistance * node.positionHint!)
      );
  }

const _optimalDistance = 100.0;
const verticalShift = -200.0;

final _random = Random();
