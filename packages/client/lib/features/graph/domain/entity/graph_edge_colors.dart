import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_tokens.dart';

/// Semantic edge stroke colors for the force-directed graph viewer.
@immutable
final class GraphEdgeColors {
  const GraphEdgeColors({
    required this.negative,
    required this.ego,
    required this.neutral,
    required this.target,
  });

  final Color negative;
  final Color ego;
  final Color neutral;

  /// Branch leading to the focused/target user in a pairwise lineage view.
  final Color target;

  factory GraphEdgeColors.fromTokens(TenturaTokens tt) => GraphEdgeColors(
        negative: tt.danger,
        ego: tt.warn,
        neutral: tt.info,
        target: tt.good,
      );
}
