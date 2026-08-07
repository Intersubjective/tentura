import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/schedule_date_format.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/coordination_log_row_chrome.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  // These fixed UTC instants are chosen close to a local day boundary for a
  // wide range of offsets (including UTC+14 / UTC-12) so a formatter that
  // forgets to convert to local time is very likely to show the wrong
  // calendar day under a non-UTC TZ, regardless of which zone the test
  // happens to run under. Run this file three times with `TZ=UTC`,
  // `TZ=Europe/Amsterdam` (DST-observing), and `TZ=Pacific/Kiritimati`
  // (UTC+14, across the international date line) — see
  // run_timezone_matrix.sh. Every assertion below is self-referential
  // (computed via the same `.toLocal()` the production code must use), so
  // it is correct under any of those TZs; it exists to catch a *missing*
  // `.toLocal()` call, not to hardcode one zone's expected string.
  final lateUtc = DateTime.utc(2026, 6, 20, 23, 30);
  final earlyUtc = DateTime.utc(2026, 1, 1, 0, 30);

  test('dateFormatYMD/timeFormatHm match direct .toLocal() formatting', () {
    for (final utc in [lateUtc, earlyUtc]) {
      final local = utc.toLocal();
      expect(dateFormatYMD(utc), DateFormat.yMd().format(local));
      expect(timeFormatHm(utc), DateFormat.Hm().format(local));
    }
  });

  test('formatScheduleDate matches direct .toLocal() formatting', () {
    final now = DateTime.utc(2026, 6, 15, 12).toLocal();
    for (final utc in [lateUtc, earlyUtc]) {
      final local = utc.toLocal();
      final expectedYear = local.year == now.year
          ? DateFormat.MMMd('en').format(local)
          : DateFormat.yMMMd('en').format(local);
      expect(
        formatScheduleDate(utc, localeName: 'en', now: now),
        expectedYear,
      );
    }
  });

  test('coordinationLogTimestampLabel matches direct .toLocal() formatting', () {
    for (final utc in [lateUtc, earlyUtc]) {
      final local = utc.toLocal();
      expect(
        coordinationLogTimestampLabel(utc),
        '${dateFormatYMD(local)} ${timeFormatHm(local)}',
      );
    }
  });

  test('compactRelativeTimeAgo diffs against the correct local day', () {
    final now = lateUtc.add(const Duration(days: 2)).toLocal();
    final l10n = lookupL10n(const Locale('en'));
    final label = compactRelativeTimeAgo(when: lateUtc, now: now, l10n: l10n);
    // Whatever the runner's TZ, "2 days ago" must be computed from the
    // same local calendar day the value converts to, not raw UTC digits.
    expect(label, l10n.relativeTimeDaysAgo(2));
  });
}
