import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/constellation_tidy_offset_layer.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';

/// The tidy offsets are a post-layout layer: every layout pass is shifted by
/// them, so a data refresh that re-runs the layout keeps the tidied positions.

void main() {
  group('tidy offset layer', () {
    test('a fresh layout pass keeps the tidied positions', () {
      final layer = ConstellationTidyOffsetLayer()
        ..recordMoves(
          from: {'A': (x: 10, y: 10), 'B': (x: 50, y: 0)},
          to: {'A': (x: 25, y: 10), 'B': (x: 50, y: -8)},
        );

      // A refresh re-runs the layout; the layout puts people at its own
      // positions, which are not the tidied ones.
      final refreshed = layer.apply({
        'A': (x: 12, y: 10),
        'B': (x: 50, y: 0),
        'C': (x: 0, y: 99),
      });

      expect(refreshed['A'], (x: 27.0, y: 10.0));
      expect(refreshed['B'], (x: 50.0, y: -8.0));
      expect(refreshed['C'], (x: 0.0, y: 99.0));
    });

    test('clearing a person puts only them back where the layout says', () {
      final layer = ConstellationTidyOffsetLayer()
        ..recordMoves(
          from: {'A': (x: 0, y: 0), 'B': (x: 0, y: 0)},
          to: {'A': (x: 5, y: 0), 'B': (x: 0, y: 5)},
        )
        ..clear({'A'});

      final placed = layer.apply({'A': (x: 1, y: 1), 'B': (x: 1, y: 1)});

      expect(placed['A'], (x: 1.0, y: 1.0));
      expect(placed['B'], (x: 1.0, y: 6.0));
    });

    test('clearing everything drops every offset', () {
      final layer = ConstellationTidyOffsetLayer()
        ..recordMoves(from: {'A': (x: 0, y: 0)}, to: {'A': (x: 5, y: 0)})
        ..clearAll();

      expect(layer.isEmpty, isTrue);
      expect(layer.apply({'A': (x: 1, y: 1)})['A'], (x: 1.0, y: 1.0));
    });

    test('people who left the Field lose their offset', () {
      final layer = ConstellationTidyOffsetLayer()
        ..recordMoves(
          from: {'A': (x: 0, y: 0), 'B': (x: 0, y: 0)},
          to: {'A': (x: 5, y: 0), 'B': (x: 0, y: 5)},
        )
        ..retainOnly({'B'});

      expect(layer.offsetOf('A'), isNull);
      expect(layer.offsetOf('B'), (x: 0.0, y: 5.0));
    });

    test('a second tidy adds to the offset of the first', () {
      final layer = ConstellationTidyOffsetLayer()
        ..recordMoves(from: {'A': (x: 0, y: 0)}, to: {'A': (x: 5, y: 0)})
        ..recordMoves(from: {'A': (x: 5, y: 0)}, to: {'A': (x: 9, y: 2)});

      expect(layer.offsetOf('A'), (x: 9.0, y: 2.0));
    });

    test('survives being saved and loaded on the same device', () {
      final layer = ConstellationTidyOffsetLayer()
        ..recordMoves(from: {'A': (x: 0, y: 0)}, to: {'A': (x: 5, y: -3)});

      final loaded = ConstellationTidyOffsetLayer.fromJson(layer.toJson());

      expect(loaded.offsetOf('A'), (x: 5.0, y: -3.0));
    });
  });
}
