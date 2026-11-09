import 'package:test/test.dart';

import 'package:tentura_server/domain/policy/public_user_availability_policy.dart';

/// Behaviour of the public availability projection in domain/policy. Its
/// import-direction checks (no storage imports; the GraphQL layer reads it
/// from domain/policy, not data/mapper) live in
/// test/architecture/layer_import_direction_test.dart.
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
}
