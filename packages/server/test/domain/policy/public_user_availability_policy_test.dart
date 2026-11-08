import 'dart:io';

import 'package:test/test.dart';

import 'package:tentura_server/domain/policy/public_user_availability_policy.dart';

/// The public availability projection is a domain rule: it lives in
/// domain/policy, free of storage imports, and the GraphQL layer reads it
/// from there rather than from data/mapper.
void main() {
  group('publicUserAvailabilityTodayUtc', () {
    test('truncates an instant to its UTC calendar date', () {
      expect(
        publicUserAvailabilityTodayUtc(DateTime.utc(2026, 3, 9, 23, 59, 59)),
        DateTime.utc(2026, 3, 9),
      );
    });

    test('a non-UTC instant is converted to UTC before truncation', () {
      final local = DateTime.utc(2026, 3, 10, 1).toLocal();
      expect(publicUserAvailabilityTodayUtc(local), DateTime.utc(2026, 3, 10));
    });
  });

  test('utcCalendarDateToWireString zero-pads to YYYY-MM-DD', () {
    expect(utcCalendarDateToWireString(DateTime.utc(987, 1, 2)), '0987-01-02');
  });

  test('policy file has no data-layer or drift imports', () {
    final source = File(
      'lib/domain/policy/public_user_availability_policy.dart',
    ).readAsStringSync();
    expect(source, isNot(contains('/data/')));
    expect(source, isNot(contains('drift')));
  });

  test('GraphQL layer no longer imports the availability data mapper', () {
    final offenders = Directory('lib/api/controllers/graphql')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where(
          (f) => f.readAsStringSync().contains(
            'data/mapper/user_availability_mapper.dart',
          ),
        )
        .map((f) => f.path)
        .toList();
    expect(offenders, isEmpty);
  });
}
