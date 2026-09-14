import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';

import '../bloc/constellation_cubit.dart';

typedef ConstellationEdgeStyle = ({
  Color color,
  double width,
  double dash,
  double gap,
});

ConstellationEdgeStyle constellationEdgeStyle(
  ConstellationEdgeKind kind,
  TenturaTokens tt,
  ColorScheme scheme,
) =>
    switch (kind) {
      ConstellationEdgeKind.tier1Path => (
          color: tt.graphEdgePath,
          width: 2.0,
          dash: 0,
          gap: 0,
        ),
      ConstellationEdgeKind.tier2Path => (
          color: tt.graphEdgePath,
          width: 2.0,
          dash: 6,
          gap: 4,
        ),
      ConstellationEdgeKind.ringStub => (
          color: tt.graphEdgePath,
          width: 1.5,
          dash: 2,
          gap: 4,
        ),
      ConstellationEdgeKind.attachment => (
          color: scheme.secondary,
          width: 1.5,
          dash: 0,
          gap: 0,
        ),
    };
