@Tags(['pg'])
library;

import 'package:test/test.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/hasura_user_availability_filter.dart';

/// tentura-vd5d: the Hasura `user_availability` select filter must agree with
/// the UTC calendar date. The existing parity test in
/// `m0148_user_availability_migration_test.dart` derives both sides from the
/// ambient clock and the connection's TimeZone, so it cannot see a drift across
/// UTC midnight. This file pins the clock instead: the `now()` in the filter is
/// shadowed by a function returning a fixed instant, and the filter expression
/// is read from `hasura/metadata.json` rather than restated here.
///
/// Expected visibility of a pause-only row is `resume_on > <UTC date of the
/// instant>`, whatever TimeZone the evaluating session runs under.
const _instants = [
  '2026-10-01T23:59:59Z',
  '2026-10-02T00:00:00Z',
  '2026-10-02T00:00:01Z',
  '2026-12-31T23:59:59Z',
  '2027-01-01T00:00:00Z',
];

const _timeZones = [
  'UTC',
  'America/Los_Angeles',
  'Asia/Kolkata',
  'Pacific/Kiritimati',
  'Pacific/Pago_Pago',
];

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0148_UTC_BOUNDARY_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0148utc',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  late DisposablePgWriterSession session;

  setUpAll(() async {
    if (skipReason != false) {
      return;
    }
    session = await setUpDisposablePgWriter(target: target);
    final writer = session.writer;
    await writer.execute('CREATE SCHEMA m0148_clock');
    await writer.execute(r'''
CREATE FUNCTION m0148_clock.now() RETURNS timestamptz
LANGUAGE sql STABLE
AS $$ SELECT current_setting('m0148_clock.instant')::timestamptz $$
''');
    // Shadow pg_catalog.now() for everything evaluated on this session.
    await writer.execute('SET search_path = m0148_clock, pg_catalog, public');
  });

  tearDownAll(() async {
    if (skipReason != false) {
      return;
    }
    await tearDownDisposablePgWriter(session: session);
  });

  /// Rows visible under the metadata filter at [instant] in [timeZone].
  Future<List<String>> visibleResumeDates({
    required String instant,
    required String timeZone,
    required String filterExpression,
  }) async {
    final writer = session.writer;
    await writer.execute("SET TIME ZONE '$timeZone'");
    await writer.execute("SET m0148_clock.instant = '$instant'");
    final utcDate = DateTime.parse(instant).toUtc();
    final candidates = [
      for (final offset in [-1, 0, 1])
        _isoDate(
          DateTime.utc(utcDate.year, utcDate.month, utcDate.day + offset),
        ),
    ];
    final rows = await writer.execute('''
SELECT resume_on::text
FROM (VALUES ${candidates.map((d) => "(DATE '$d')").join(', ')}) AS v(resume_on)
WHERE resume_on > $filterExpression
ORDER BY resume_on
''');
    return rows.map((row) => row[0]! as String).toList();
  }

  test(
    'the clock shadow pins the filter instant',
    () async {
      final rows = await session.writer.execute(
        "SET m0148_clock.instant = '2026-10-01T23:59:59Z'",
      );
      expect(rows, isEmpty);
      final now = await session.writer.execute(
        "SELECT to_char(now() AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS')",
      );
      expect(now.single.single, '2026-10-01 23:59:59');
    },
    skip: skipReason,
  );

  test(
    'UTC session: filter agrees with the UTC calendar date across midnight',
    () async {
      final expression = hasuraUserAvailabilityResumeOnExpression();
      for (final instant in _instants) {
        final visible = await visibleResumeDates(
          instant: instant,
          timeZone: 'UTC',
          filterExpression: expression,
        );
        expect(visible, [_nextUtcDate(instant)], reason: 'instant $instant');
      }
    },
    skip: skipReason,
  );

  test(
    'filter agrees with the UTC calendar date in every session TimeZone',
    () async {
      final expression = hasuraUserAvailabilityResumeOnExpression();
      final mismatches = <String>[];
      for (final timeZone in _timeZones) {
        for (final instant in _instants) {
          final visible = await visibleResumeDates(
            instant: instant,
            timeZone: timeZone,
            filterExpression: expression,
          );
          final expected = [_nextUtcDate(instant)];
          if (visible.join(',') != expected.join(',')) {
            mismatches.add(
              '$timeZone @ $instant: visible $visible, expected $expected',
            );
          }
        }
      }
      expect(
        mismatches,
        isEmpty,
        reason:
            'Hasura filter `resume_on > $expression` must hide a pause-only '
            'row whose resume_on is the current UTC date, in any session '
            'TimeZone',
      );
    },
    skip: skipReason,
  );
}

String _nextUtcDate(String instant) {
  final utc = DateTime.parse(instant).toUtc();
  return _isoDate(DateTime.utc(utc.year, utc.month, utc.day + 1));
}

String _isoDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';
