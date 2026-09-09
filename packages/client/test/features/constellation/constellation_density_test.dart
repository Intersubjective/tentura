import 'dart:ui' show Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_density.dart';

Size _viewport({double width = 1200, double height = 900}) =>
    Size(width, height);

void main() {
  group('constellationLabelBudget', () {
    test('never exceeds (3, 150) ceilings', () {
      final budget = constellationLabelBudget(
        viewport: _viewport(width: 4000, height: 3000),
        textScaleFactor: 0.5,
      );

      expect(budget.perPerson, lessThanOrEqualTo(3));
      expect(budget.total, lessThanOrEqualTo(150));
    });

    test('reference viewport at text scale 1.0 reaches ceilings', () {
      final budget = constellationLabelBudget(
        viewport: _viewport(),
        textScaleFactor: 1.0,
      );

      expect(budget, (perPerson: 3, total: 150));
    });

    test('smaller viewport lowers the budget monotonically', () {
      final large = constellationLabelBudget(
        viewport: _viewport(width: 1200, height: 900),
        textScaleFactor: 1.0,
      );
      final small = constellationLabelBudget(
        viewport: _viewport(width: 600, height: 450),
        textScaleFactor: 1.0,
      );

      expect(small.perPerson, lessThanOrEqualTo(large.perPerson));
      expect(small.total, lessThanOrEqualTo(large.total));
      expect(small.perPerson, lessThan(large.perPerson));
      expect(small.total, lessThan(large.total));
    });

    test('larger text scale lowers the budget monotonically', () {
      final normal = constellationLabelBudget(
        viewport: _viewport(),
        textScaleFactor: 1.0,
      );
      final largeText = constellationLabelBudget(
        viewport: _viewport(),
        textScaleFactor: 2.0,
      );

      expect(largeText.perPerson, lessThanOrEqualTo(normal.perPerson));
      expect(largeText.total, lessThanOrEqualTo(normal.total));
      expect(largeText.perPerson, lessThan(normal.perPerson));
      expect(largeText.total, lessThan(normal.total));
    });
  });

  group('allocateVisibleRequests', () {
    test('one prolific author cannot consume the whole budget', () {
      final prolific = List.generate(40, (i) => 'p${i.toString().padLeft(2, '0')}');
      final others = {
        for (var i = 0; i < 9; i++)
          'author-$i': List.generate(5, (j) => 'r-$i-$j'),
      };

      final requestIdsByAuthor = {
        'prolific': prolific,
        ...others,
      };

      final allocated = allocateVisibleRequests(
        requestIdsByAuthor: requestIdsByAuthor,
        budget: (perPerson: 3, total: 30),
      );

      final totalLabels =
          allocated.values.fold<int>(0, (sum, ids) => sum + ids.length);
      expect(totalLabels, 30);
      expect(allocated['prolific']!.length, 3);

      for (final author in requestIdsByAuthor.keys) {
        expect(allocated[author], isNotEmpty);
      }
    });

    test('every author with requests gets at least one label while budget remains', () {
      final requestIdsByAuthor = {
        'c': ['c1', 'c2'],
        'a': ['a1'],
        'b': ['b1', 'b2', 'b3'],
      };

      final allocated = allocateVisibleRequests(
        requestIdsByAuthor: requestIdsByAuthor,
        budget: (perPerson: 2, total: 4),
      );

      expect(allocated['a'], ['a1']);
      expect(allocated['b'], ['b1', 'b2']);
      expect(allocated['c'], ['c1']);
      expect(
        allocated.values.fold<int>(0, (sum, ids) => sum + ids.length),
        4,
      );
    });

    test('allocation is deterministic under shuffled map iteration order', () {
      final requestIdsByAuthor = {
        'z': ['z1', 'z2'],
        'a': ['a1', 'a2'],
        'm': ['m1'],
      };

      final expected = allocateVisibleRequests(
        requestIdsByAuthor: requestIdsByAuthor,
        budget: (perPerson: 2, total: 5),
      );

      final shuffled = {
        'm': ['m1'],
        'z': ['z1', 'z2'],
        'a': ['a1', 'a2'],
      };

      final actual = allocateVisibleRequests(
        requestIdsByAuthor: shuffled,
        budget: (perPerson: 2, total: 5),
      );

      expect(actual, expected);
      expect(actual['a'], ['a1', 'a2']);
      expect(actual['z'], ['z1', 'z2']);
      expect(actual['m'], ['m1']);
    });

    test('round-robin respects per-person ceiling', () {
      final requestIdsByAuthor = {
        'a': ['a1', 'a2', 'a3', 'a4'],
        'b': ['b1', 'b2', 'b3', 'b4'],
      };

      final allocated = allocateVisibleRequests(
        requestIdsByAuthor: requestIdsByAuthor,
        budget: (perPerson: 2, total: 100),
      );

      expect(allocated['a'], ['a1', 'a2']);
      expect(allocated['b'], ['b1', 'b2']);
    });
  });
}
