import 'package:flutter/material.dart';

import 'node_details.dart';

@immutable
final class EdgeDetails {
  const EdgeDetails({
    required this.source,
    required this.destination,
    required this.color,
    this.strokeWidth = 2,
    this.isReciprocal = false,
  });

  final NodeDetails source;
  final NodeDetails destination;
  final Color color;
  final double strokeWidth;
  final bool isReciprocal;

  @override
  int get hashCode =>
      source.hashCode ^
      destination.hashCode ^
      color.hashCode ^
      strokeWidth.hashCode ^
      isReciprocal.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EdgeDetails &&
          runtimeType == other.runtimeType &&
          source == other.source &&
          destination == other.destination &&
          strokeWidth == other.strokeWidth &&
          color == other.color &&
          isReciprocal == other.isReciprocal;

  EdgeDetails copyWith({
    NodeDetails? source,
    NodeDetails? destination,
    double? strokeWidth,
    Color? color,
    bool? isReciprocal,
  }) => EdgeDetails(
    source: source ?? this.source,
    destination: destination ?? this.destination,
    strokeWidth: strokeWidth ?? this.strokeWidth,
    color: color ?? this.color,
    isReciprocal: isReciprocal ?? this.isReciprocal,
  );
}
