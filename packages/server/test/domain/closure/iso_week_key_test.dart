import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/iso_week_key.dart';

/// A17: `stale_request:<beacon>:<ISO week-year>-W<ISO week>` needs the ISO
/// week-year, which differs from the calendar year around New Year.
void main() {
  test('2026-12-31 is ISO week 53 of 2026', () {
    expect(isoWeekKey(DateTime.utc(2026, 12, 31)), '2026-W53');
  });

  test('2027-01-01 still belongs to 2026-W53', () {
    expect(isoWeekKey(DateTime.utc(2027)), '2026-W53');
  });

  test('2027-01-04 starts 2027-W01', () {
    expect(isoWeekKey(DateTime.utc(2027, 1, 4)), '2027-W01');
  });

  test('week numbers are zero-padded and Sunday closes its week', () {
    expect(isoWeekKey(DateTime.utc(2026, 10)), '2026-W40');
    expect(isoWeekKey(DateTime.utc(2026, 10, 4, 23, 59)), '2026-W40');
    expect(isoWeekKey(DateTime.utc(2026, 10, 5)), '2026-W41');
  });

  test('early-January dates may belong to the previous ISO year', () {
    expect(isoWeekKey(DateTime.utc(2025, 12, 29)), '2026-W01');
    expect(isoWeekKey(DateTime.utc(2024, 12, 30)), '2025-W01');
  });
}
