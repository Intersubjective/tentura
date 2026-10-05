import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/graph/domain/entity/graph_edge_colors.dart';
import 'package:tentura/features/graph/ui/utils/graph_edge_style.dart';

const _colors = GraphEdgeColors(
  negative: Colors.red,
  ego: Colors.orange,
  neutral: Colors.blue,
  target: Colors.green,
);

/// Everything about a style except its color.
Object _shape(GraphEdgeKind kind) {
  final s = graphEdgeStyle(kind, _colors);
  return (s.width, s.pattern, s.crossMark);
}

void main() {
  test('trust graph edge kinds differ without color', () {
    final shapes = {
      for (final k in [
        GraphEdgeKind.ego,
        GraphEdgeKind.other,
        GraphEdgeKind.negative,
      ])
        _shape(k),
    };
    expect(shapes, hasLength(3));
  });

  test('invite tree edge kinds differ without color', () {
    final shapes = {
      for (final k in [
        GraphEdgeKind.genealogyEgo,
        GraphEdgeKind.genealogyTarget,
        GraphEdgeKind.genealogyNeutral,
      ])
        _shape(k),
    };
    expect(shapes, hasLength(3));
  });

  test('edge legend strings name meaning, not color (EN + RU)', () {
    final colorWords = RegExp(
      r'\b(gold|blue|red|green)\b|золот|синий|красн|зел[её]н',
    );
    for (final lang in ['en', 'ru']) {
      final arb =
          jsonDecode(File('l10n/app_$lang.arb').readAsStringSync())
              as Map<String, dynamic>;
      for (final entry in arb.entries) {
        if (!entry.key.startsWith('graphLegendEdge')) continue;
        final value = (entry.value as String).toLowerCase();
        expect(
          colorWords.hasMatch(value),
          isFalse,
          reason: '$lang ${entry.key} names a color: ${entry.value}',
        );
      }
    }
  });
}
