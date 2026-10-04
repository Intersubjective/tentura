import 'package:flutter/material.dart';

import 'graph_edge_pattern.dart';
import 'node_details.dart';

@immutable
final class EdgeDetails {
  const EdgeDetails({
    required this.source,
    required this.destination,
    required this.color,
    this.strokeWidth = 2,
    this.isReciprocal = false,
    this.pattern = GraphEdgePattern.solid,
    this.crossMark = false,
    this.arrowAtSource = false,
    this.arrowAtDestination = false,
    String? semanticId,
  }) : _semanticId = semanticId;

  final NodeDetails source;
  final NodeDetails destination;
  final Color color;
  final double strokeWidth;
  final bool isReciprocal;
  final GraphEdgePattern pattern;

  /// Draws a ✕ at the edge midpoint (negative connection).
  final bool crossMark;

  /// Arrowheads showing direction; drawn only where the view asks for them
  /// (e.g. on the selected node's edges) to keep the graph quiet.
  final bool arrowAtSource;
  final bool arrowAtDestination;

  final String? _semanticId;

  /// Identity of the edge beyond its endpoints, so parallel edges of different
  /// kinds stay distinct. Defaults to `'src->dst'` (scene node ids).
  String get semanticId =>
      _semanticId ?? '${source.graphNodeId}->${destination.graphNodeId}';

  @override
  int get hashCode =>
      source.hashCode ^
      destination.hashCode ^
      color.hashCode ^
      strokeWidth.hashCode ^
      isReciprocal.hashCode ^
      pattern.hashCode ^
      crossMark.hashCode ^
      arrowAtSource.hashCode ^
      arrowAtDestination.hashCode ^
      semanticId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgeDetails &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          destination == other.destination &&
          strokeWidth == other.strokeWidth &&
          color == other.color &&
          isReciprocal == other.isReciprocal &&
          pattern == other.pattern &&
          crossMark == other.crossMark &&
          arrowAtSource == other.arrowAtSource &&
          arrowAtDestination == other.arrowAtDestination &&
          semanticId == other.semanticId;

  EdgeDetails copyWith({
    NodeDetails? source,
    NodeDetails? destination,
    double? strokeWidth,
    Color? color,
    bool? isReciprocal,
    GraphEdgePattern? pattern,
    bool? crossMark,
    bool? arrowAtSource,
    bool? arrowAtDestination,
  }) => EdgeDetails(
    source: source ?? this.source,
    destination: destination ?? this.destination,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    color: color ?? this.color,
    isReciprocal: isReciprocal ?? this.isReciprocal,
    pattern: pattern ?? this.pattern,
    crossMark: crossMark ?? this.crossMark,
    arrowAtSource: arrowAtSource ?? this.arrowAtSource,
    arrowAtDestination: arrowAtDestination ?? this.arrowAtDestination,
    semanticId: _semanticId,
  );
}
