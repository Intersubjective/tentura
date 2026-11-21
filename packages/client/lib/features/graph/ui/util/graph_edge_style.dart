import 'package:flutter/material.dart';

import '../../domain/entity/graph_edge_colors.dart';
import '../../domain/entity/graph_edge_pattern.dart';

/// Semantic edge kinds on the trust / forwards / invite-tree graphs.
enum GraphEdgeKind {
  /// Touches the viewer (trust, forwards).
  ego,

  /// Any other positive connection.
  other,

  /// Negative connection (trust graph).
  negative,

  /// The viewer's invite branch.
  genealogyEgo,

  /// The other person's invite branch.
  genealogyTarget,

  /// Shared trunk of the invite tree.
  genealogyNeutral,
}

/// Single source of truth for how each edge kind is stroked. The graph painter
/// and the legend both read it, so samples never drift from the canvas.
///
/// Every kind carries a non-color cue (width, dash/dot pattern, ✕ mark) so the
/// kinds stay distinguishable in grayscale; color is kept as a second cue.
typedef GraphEdgeStyle = ({
  Color color,
  double width,
  GraphEdgePattern pattern,
  bool crossMark,
});

const _strongWidth = 3.5;
const _thinWidth = 1.5;
const _negativeWidth = 2.0;

GraphEdgeStyle graphEdgeStyle(GraphEdgeKind kind, GraphEdgeColors colors) =>
    switch (kind) {
      GraphEdgeKind.ego || GraphEdgeKind.genealogyEgo => (
        color: colors.ego,
        width: _strongWidth,
        pattern: GraphEdgePattern.solid,
        crossMark: false,
      ),
      GraphEdgeKind.other || GraphEdgeKind.genealogyNeutral => (
        color: colors.neutral,
        width: _thinWidth,
        pattern: GraphEdgePattern.solid,
        crossMark: false,
      ),
      GraphEdgeKind.negative => (
        color: colors.negative,
        width: _negativeWidth,
        pattern: GraphEdgePattern.dashed,
        crossMark: true,
      ),
      GraphEdgeKind.genealogyTarget => (
        color: colors.target,
        width: _strongWidth,
        pattern: GraphEdgePattern.dotted,
        crossMark: false,
      ),
    };
