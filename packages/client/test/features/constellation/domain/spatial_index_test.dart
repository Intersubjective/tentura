import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/constellation/domain/layout/layout_geometry.dart';
import 'package:tentura/features/constellation/domain/layout/spatial_index.dart';

LRect _r(double l, double t, double r, double b) =>
    (left: l, top: t, right: r, bottom: b);

void main() {
  group('BruteForceIndex', () {
    late SpatialIndex index;
    setUp(() => index = BruteForceIndex());

    test('empty index has no overlaps', () {
      expect(index.length, 0);
      expect(index.queryOverlaps(_r(0, 0, 10, 10)), isEmpty);
    });

    test('returns overlapping ids in insertion order', () {
      index
        ..insert('a', _r(0, 0, 10, 10))
        ..insert('b', _r(20, 20, 30, 30))
        ..insert('c', _r(5, 5, 25, 25));
      expect(index.queryOverlaps(_r(8, 8, 22, 22)), ['a', 'b', 'c']);
      expect(index.queryOverlaps(_r(0, 0, 4, 4)), ['a']);
    });

    test('touching edges and corners do not overlap', () {
      index.insert('a', _r(0, 0, 10, 10));
      expect(index.queryOverlaps(_r(10, 0, 20, 10)), isEmpty);
      expect(index.queryOverlaps(_r(10, 10, 20, 20)), isEmpty);
    });

    test('exceptId skips that id', () {
      index
        ..insert('a', _r(0, 0, 10, 10))
        ..insert('b', _r(0, 0, 10, 10));
      expect(index.queryOverlaps(_r(0, 0, 10, 10), exceptId: 'a'), ['b']);
    });

    test('insert replaces an existing id', () {
      index
        ..insert('a', _r(0, 0, 10, 10))
        ..insert('a', _r(100, 100, 110, 110));
      expect(index.length, 1);
      expect(index.queryOverlaps(_r(0, 0, 10, 10)), isEmpty);
      expect(index.queryOverlaps(_r(100, 100, 105, 105)), ['a']);
    });

    test('remove reports presence and drops the id', () {
      index.insert('a', _r(0, 0, 10, 10));
      expect(index.remove('a'), isTrue);
      expect(index.remove('a'), isFalse);
      expect(index.length, 0);
      expect(index.queryOverlaps(_r(0, 0, 10, 10)), isEmpty);
    });
  });
}
