import 'dart:math' as math;
import 'dart:ui' show PathMetric;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/constellation/ui/utils/constellation_edge_style.dart';

List<PathMetric> _contours(Path path) => path.computeMetrics().toList();

double _totalLength(Path path) =>
    _contours(path).fold(0, (sum, metric) => sum + metric.length);

void main() {
  group('constellationDashedCirclePath', () {
    const center = Offset(40, -25);
    const radius = 20.0;

    test('breaks the outline into several separate dashes', () {
      final path = constellationDashedCirclePath(
        center,
        radius,
        dash: 6,
        gap: 4,
      );

      // A closed solid circle would be one contour.
      expect(_contours(path).length, greaterThan(8));
    });

    test('keeps every dash on the circle', () {
      final path = constellationDashedCirclePath(
        center,
        radius,
        dash: 6,
        gap: 4,
      );

      for (final metric in _contours(path)) {
        for (var d = 0.0; d <= metric.length; d += 0.5) {
          final point = metric.getTangentForOffset(d)!.position;
          expect(
            (point - center).distance,
            closeTo(radius, 0.05),
            reason: 'a point of the dash left the circle',
          );
        }
      }
    });

    test('covers about dash / (dash + gap) of the circumference', () {
      final path = constellationDashedCirclePath(
        center,
        radius,
        dash: 6,
        gap: 4,
      );

      const circumference = 2 * math.pi * radius;
      final covered = _totalLength(path) / circumference;
      expect(covered, inInclusiveRange(0.5, 0.7));
    });

    test('a longer gap leaves less of the circle drawn', () {
      final tight = constellationDashedCirclePath(
        center,
        radius,
        dash: 6,
        gap: 2,
      );
      final loose = constellationDashedCirclePath(
        center,
        radius,
        dash: 6,
        gap: 8,
      );

      expect(_totalLength(loose), lessThan(_totalLength(tight)));
    });

    test('is the same path for the same circle', () {
      final first = constellationDashedCirclePath(
        center,
        radius,
        dash: 6,
        gap: 4,
      );
      final second = constellationDashedCirclePath(
        center,
        radius,
        dash: 6,
        gap: 4,
      );

      expect(second.getBounds(), first.getBounds());
      expect(_contours(second).length, _contours(first).length);
    });

    test('a degenerate circle draws nothing', () {
      final path = constellationDashedCirclePath(
        center,
        0,
        dash: 6,
        gap: 4,
      );

      expect(_totalLength(path), 0);
    });
  });

  group('temporary presence link style', () {
    for (final theme in [TenturaTheme.light(), TenturaTheme.dark()]) {
      test('is a thin dashed stroke without end dots '
          '(${theme.brightness.name})', () {
        final tt = theme.extension<TenturaTokens>()!;
        final style = constellationEdgeStyle(
          ConstellationEdgeKind.temporaryPresence,
          tt,
          theme.colorScheme,
        );
        final pathStyle = constellationEdgeStyle(
          ConstellationEdgeKind.tier1Path,
          tt,
          theme.colorScheme,
        );

        expect(style.dash, greaterThan(0));
        expect(style.gap, greaterThan(0));
        expect(style.width, lessThan(pathStyle.width));
        expect(style.endDots, isFalse);
        expect(style.twin, isFalse);
      });
    }
  });
}
