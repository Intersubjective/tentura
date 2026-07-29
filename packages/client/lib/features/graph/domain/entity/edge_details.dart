import 'package:flutter/material.dart';
import 'package:force_directed_graphview/force_directed_graphview.dart'
    show EdgeBase, NodeBase;

@immutable
final class EdgeDetails<N extends NodeBase> extends EdgeBase<N> {
  const EdgeDetails({
    required super.source,
    required super.destination,
    required this.color,
    this.strokeWidth = 2,
    this.isReciprocal = false,
  });

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

  @override
  EdgeDetails<N> replaceNode({
    N? source,
    N? destination,
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
