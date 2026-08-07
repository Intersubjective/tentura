import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';

void main() {
  group('scheduleDateTimeToIso', () {
    test('null passes through', () {
      expect(scheduleDateTimeToIso(null), isNull);
    });

    test('local midnight always serializes with an explicit UTC offset', () {
      final localMidnight = DateTime(2026, 6, 20); // built local, no .utc()
      final iso = scheduleDateTimeToIso(localMidnight)!;
      expect(iso, endsWith('Z'));
      expect(DateTime.parse(iso).isUtc, isTrue);
      // Round-trips to the same instant the picker meant, not a shifted one.
      expect(DateTime.parse(iso), localMidnight.toUtc());
    });

    test('an already-UTC value is unchanged in meaning', () {
      final utcValue = DateTime.utc(2026, 6, 20, 14, 30);
      final iso = scheduleDateTimeToIso(utcValue)!;
      expect(DateTime.parse(iso), utcValue);
    });
  });
}
