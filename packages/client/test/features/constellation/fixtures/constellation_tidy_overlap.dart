import 'dart:math' as math;

import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

/// Every overlap among people drawn as a circle of [radius] with a label box
/// of [labelSize] centred under it: node over node, label over label and
/// node over another person's label. Empty when the picture is clean.
List<String> tidyOverlaps(
  Map<String, LPoint> placed, {
  required double radius,
  required LSize labelSize,
}) {
  LRect labelOf(LPoint p) {
    final cy = p.y + radius + labelSize.h / 2;
    return (
      left: p.x - labelSize.w / 2,
      top: cy - labelSize.h / 2,
      right: p.x + labelSize.w / 2,
      bottom: cy + labelSize.h / 2,
    );
  }

  bool nodeHitsLabel(LPoint node, LRect box) {
    final nx = node.x.clamp(box.left, box.right);
    final ny = node.y.clamp(box.top, box.bottom);
    return math.sqrt(math.pow(node.x - nx, 2) + math.pow(node.y - ny, 2)) <
        radius - 1e-6;
  }

  bool boxesHit(LRect a, LRect b) =>
      a.left < b.right - 1e-6 &&
      b.left < a.right - 1e-6 &&
      a.top < b.bottom - 1e-6 &&
      b.top < a.bottom - 1e-6;

  final problems = <String>[];
  final ids = placed.keys.toList();
  for (var i = 0; i < ids.length; i++) {
    for (var j = 0; j < ids.length; j++) {
      if (i == j) continue;
      final a = placed[ids[i]]!;
      final b = placed[ids[j]]!;
      if (i < j) {
        final d = math.sqrt(math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2));
        if (d < 2 * radius - 1e-6) {
          problems.add('node ${ids[i]} over node ${ids[j]}');
        }
        if (boxesHit(labelOf(a), labelOf(b))) {
          problems.add('label ${ids[i]} over label ${ids[j]}');
        }
      }
      if (nodeHitsLabel(a, labelOf(b))) {
        problems.add('node ${ids[i]} over label of ${ids[j]}');
      }
    }
  }
  return problems;
}
