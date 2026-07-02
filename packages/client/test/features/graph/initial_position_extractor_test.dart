import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/graph/domain/entity/node_details.dart';
import 'package:tentura/features/graph/ui/utils/initial_position_extractor.dart';

void main() {
  const canvas = Size(800, 600);
  final center = canvas.center(Offset.zero);

  group('initialPositionExtractor', () {
    test('uses vertical hint ladder: higher hint moves north of center', () {
      final south = initialPositionExtractor(
        const UserNode(user: Profile(id: 'a'), positionHint: 0),
        canvas,
      );
      final mid = initialPositionExtractor(
        const UserNode(user: Profile(id: 'b'), positionHint: 2),
        canvas,
      );
      final north = initialPositionExtractor(
        const UserNode(user: Profile(id: 'c'), positionHint: 4),
        canvas,
      );

      expect(south.dy, greaterThan(center.dy));
      expect(mid.dy, lessThan(south.dy));
      expect(north.dy, lessThan(mid.dy));
    });

    test('hint 0 sits 200px below canvas center on y axis', () {
      final offset = initialPositionExtractor(
        const UserNode(user: Profile(id: 'ego'), positionHint: 0),
        canvas,
      );

      expect(offset.dy, closeTo(center.dy + 200, 0.001));
    });

    test('hint 4 sits 200px above canvas center on y axis', () {
      final offset = initialPositionExtractor(
        const UserNode(user: Profile(id: 'focus'), positionHint: 4),
        canvas,
      );

      expect(offset.dy, closeTo(center.dy - 200, 0.001));
    });

    test('large hints stay within the vertical hint band', () {
      final offset = initialPositionExtractor(
        const UserNode(user: Profile(id: 'late'), positionHint: 25),
        canvas,
      );

      expect(offset.dy, inInclusiveRange(center.dy - 200, center.dy + 200));
    });

    test('x jitter stays within ±1 px of center', () {
      final offset = initialPositionExtractor(
        const UserNode(user: Profile(id: 'n'), positionHint: 1),
        canvas,
      );

      expect(offset.dx - center.dx, inInclusiveRange(-1.0, 1.0));
    });

    test('falls back to library default for nodes without positionHint', () {
      final withHint = initialPositionExtractor(
        const UserNode(user: Profile(id: 'hinted'), positionHint: 0),
        canvas,
      );
      final fallback = initialPositionExtractor(
        BeaconNode(
          beacon: Beacon(
            id: 'B1',
            title: 'Beacon',
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
          ),
        ),
        canvas,
      );

      expect(fallback, isNot(equals(withHint)));
    });
  });
}
