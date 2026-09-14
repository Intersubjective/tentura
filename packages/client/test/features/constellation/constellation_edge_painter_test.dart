import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/widget/constellation_body.dart';
import 'package:tentura/features/graph/domain/entity/edge_details.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/graph_scene_ids.dart';

void main() {
  test('effectiveWidth scales stroke when zoomed out', () {
    expect(ConstellationEdgePainter.effectiveWidth(2.0, 0.5), 4.0);
    expect(ConstellationEdgePainter.effectiveWidth(2.0, 1.0), 2.0);
    expect(ConstellationEdgePainter.effectiveWidth(2.0, 1.5), 2.0);
  });

  test('paints tier-1 edge without throwing', () {
    final src = FieldPersonNode(
      person: const Profile(id: 'a', displayName: 'A'),
      ring: 0,
      isKept: true,
      size: 40,
    );
    final dst = FieldPersonNode(
      person: const Profile(id: 'b', displayName: 'B'),
      ring: 1,
      isKept: true,
      size: 40,
    );
    final pairKey = '${tenturaGraphNodeId(src)}->${tenturaGraphNodeId(dst)}';
    final painter = ConstellationEdgePainter(
      edgeKindByPair: {pairKey: ConstellationEdgeKind.tier1Path},
      tt: TenturaTokens.light,
      scheme: const ColorScheme.light(),
      repaint: const _NeverListenable(),
      cameraScale: () => 0.5,
    );
    final edge = EdgeDetails(
      source: src,
      destination: dst,
      color: Colors.transparent,
    );
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    painter.paint(canvas, edge, const Offset(0, 0), const Offset(100, 0));
    expect(
      ConstellationEdgePainter.effectiveWidth(2.0, 0.5),
      4.0,
    );
  });
}

class _NeverListenable implements Listenable {
  const _NeverListenable();

  @override
  void addListener(VoidCallback listener) {}

  @override
  void removeListener(VoidCallback listener) {}
}
