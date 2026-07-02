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
  final hint = node.positionHint!;
  final verticalSlot = hint % _verticalHintSlots;
  final horizontalSlot = hint ~/ _verticalHintSlots;

  return canvasSize.center(Offset.zero) +
      Offset(
        _horizontalOffsetForSlot(horizontalSlot) +
            (_random.nextDouble() * 2 - 1) * (_optimalDistance * 0.01),
        -(verticalShift + _optimalDistance * verticalSlot),
      );
}

double _horizontalOffsetForSlot(int slot) {
  if (slot == 0) {
    return 0;
  }
  final lane = (slot + 1) ~/ 2;
  final direction = slot.isOdd ? 1 : -1;
  return direction * lane * _optimalDistance;
}

const _optimalDistance = 100.0;
const _verticalHintSlots = 5;
const verticalShift = -200.0;

final _random = Random();
