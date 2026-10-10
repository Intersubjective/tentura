import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/layout/grid_index.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';

/// The index adopted for production: the U36 benchmark decision (journal,
/// "Choice: grid"). Swap this one factory if the decision ever changes.
SpatialIndex _newChosenIndex() => GridIndex();

const _randomizedCaseCount = 1000;

LRect _r(double l, double t, double r, double b) =>
    (left: l, top: t, right: r, bottom: b);

/// Footprints the layout actually produces (nodes and labels) plus a few
/// degenerate and oversized shapes.
const _sizes = <(double, double)>[
  (72, 72),
  (144, 56),
  (196, 36),
  (96, 112),
  (0, 0),
  (1, 300),
  (900, 700),
];

LRect _randomRect(math.Random rnd, {required double field}) {
  final (w, h) = _sizes[rnd.nextInt(_sizes.length)];
  // Snapping to a coarse lattice a third of the time makes touching edges and
  // corners, and cell-boundary alignment, common instead of vanishingly rare.
  double coord() => rnd.nextInt(3) == 0
      ? (rnd.nextInt((field / 8).ceil() * 2) - field / 8) * 8
      : (rnd.nextDouble() - 0.5) * field;
  final x = coord();
  final y = coord();
  return _r(x, y, x + w, y + h);
}

void main() {
  group('chosen spatial index', () {
    late SpatialIndex index;
    setUp(() => index = _newChosenIndex());

    test('is a SpatialIndex', () {
      expect(index, isA<SpatialIndex>());
    });

    test('empty index has no overlaps', () {
      expect(index.length, 0);
      expect(index.queryOverlaps(_r(0, 0, 10, 10)), isEmpty);
    });

    test('returns every overlapping id and no others', () {
      index
        ..insert('a', _r(0, 0, 10, 10))
        ..insert('b', _r(20, 20, 30, 30))
        ..insert('c', _r(5, 5, 25, 25));
      expect(
        index.queryOverlaps(_r(8, 8, 22, 22)),
        unorderedEquals(['a', 'b', 'c']),
      );
      expect(index.queryOverlaps(_r(0, 0, 4, 4)), unorderedEquals(['a']));
    });

    test('touching edges and corners do not overlap', () {
      index.insert('a', _r(0, 0, 10, 10));
      expect(index.queryOverlaps(_r(10, 0, 20, 10)), isEmpty);
      expect(index.queryOverlaps(_r(10, 10, 20, 20)), isEmpty);
    });

    test('large rectangle spanning many buckets reports no false overlap', () {
      index.insert('a', _r(0, 0, 900, 700));
      expect(index.queryOverlaps(_r(900, 0, 1000, 700)), isEmpty);
      expect(index.queryOverlaps(_r(-100, -100, 0, 0)), isEmpty);
      expect(
        index.queryOverlaps(_r(450, 350, 460, 360)),
        unorderedEquals(['a']),
      );
    });

    test('finds rectangles at negative coordinates', () {
      index.insert('a', _r(-300, -300, -200, -250));
      expect(
        index.queryOverlaps(_r(-250, -280, -240, -260)),
        unorderedEquals(['a']),
      );
    });

    test('exceptId skips that id', () {
      index
        ..insert('a', _r(0, 0, 10, 10))
        ..insert('b', _r(0, 0, 10, 10));
      expect(
        index.queryOverlaps(_r(0, 0, 10, 10), exceptId: 'a'),
        unorderedEquals(['b']),
      );
    });

    test('insert replaces an existing id instead of duplicating it', () {
      index
        ..insert('a', _r(0, 0, 10, 10))
        ..insert('b', _r(0, 0, 10, 10))
        ..insert('a', _r(0, 0, 10, 10));
      expect(index.length, 2);
      expect(
        index.queryOverlaps(_r(0, 0, 10, 10)),
        unorderedEquals(['a', 'b']),
      );
      index.insert('a', _r(500, 500, 510, 510));
      expect(index.queryOverlaps(_r(0, 0, 10, 10)), unorderedEquals(['b']));
      expect(
        index.queryOverlaps(_r(500, 500, 505, 505)),
        unorderedEquals(['a']),
      );
    });

    test('remove reports presence and drops the id', () {
      index.insert('a', _r(0, 0, 10, 10));
      expect(index.remove('a'), isTrue);
      expect(index.remove('a'), isFalse);
      expect(index.length, 0);
      expect(index.queryOverlaps(_r(0, 0, 10, 10)), isEmpty);
    });
  });

  group('chosen spatial index vs BruteForceIndex oracle', () {
    test('returns the same overlap sets over 1000 randomized cases', () {
      var cases = 0;
      var nonEmpty = 0;
      for (var seed = 0; seed < _randomizedCaseCount; seed++) {
        cases++;
        final rnd = math.Random(seed);
        final oracle = BruteForceIndex();
        final grid = _newChosenIndex();
        final n = 1 + rnd.nextInt(120);
        final field = 200.0 + rnd.nextInt(2400);
        final ids = List.generate(n, (i) => 'n$i');

        for (final id in ids) {
          final rect = _randomRect(rnd, field: field);
          oracle.insert(id, rect);
          grid.insert(id, rect);
        }

        // A burst of mutations: move, remove, re-add.
        for (var step = 0; step < 30; step++) {
          final id = ids[rnd.nextInt(n)];
          if (rnd.nextInt(4) == 0) {
            expect(
              grid.remove(id),
              oracle.remove(id),
              reason: 'seed $seed step $step remove $id',
            );
          } else {
            final rect = _randomRect(rnd, field: field);
            oracle.insert(id, rect);
            grid.insert(id, rect);
          }
          expect(grid.length, oracle.length, reason: 'seed $seed step $step');
        }

        for (var q = 0; q < 12; q++) {
          final probe = _randomRect(rnd, field: field);
          final except = rnd.nextBool() ? ids[rnd.nextInt(n)] : null;
          final expected = oracle.queryOverlaps(probe, exceptId: except);
          expect(
            grid.queryOverlaps(probe, exceptId: except),
            unorderedEquals(expected),
            reason: 'seed $seed query $q probe $probe except $except',
          );
          if (expected.isNotEmpty) nonEmpty++;
        }
      }
      // Guard against a degenerate generator that never produces overlaps.
      expect(cases, _randomizedCaseCount);
      expect(nonEmpty, greaterThan(1000));
    });
  });
}
