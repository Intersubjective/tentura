import 'dart:io';

import 'package:test/test.dart';

/// Guards against Drift/`drift_postgres` binding a plain [DateTime] as bigint
/// epoch millis when comparing to Postgres `timestamptz` columns.
///
/// That mismatch yields:
///   `operator does not exist: timestamp with time zone < bigint`
/// and was the root cause of `beaconClose` failing inside
/// [AttentionExpiryRepository.lockExpiredReviewWindowBeaconIds].
///
/// Allowed binds for timestamptz parameters:
/// - `Variable(PgDateTime(...), PgTypes.timestampWithTimezone)`
/// - `Variable(TypedValue(Type.timestampTz, ...))`
/// - ISO-8601 `Variable<String>(...)` **only when** the SQL casts `$N::timestamptz`
/// - SQL `now()` with no bind
void main() {
  final repoRoot = Directory('lib/data/repository');
  assert(repoRoot.existsSync(), 'run from packages/server');

  final dartFiles = repoRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('forbids Variable<DateTime> in data repositories', () {
    final hits = <String>[];
    for (final file in dartFiles) {
      final text = file.readAsStringSync();
      for (final match in RegExp(r'Variable\s*<\s*DateTime\s*>').allMatches(text)) {
        final line = _lineNumber(text, match.start);
        hits.add('${file.path}:$line');
      }
    }
    expect(
      hits,
      isEmpty,
      reason:
          'Use Variable(PgDateTime(now), PgTypes.timestampWithTimezone) or '
          'ISO string + \$N::timestamptz — not Variable<DateTime> (binds as bigint). '
          'Hits: $hits',
    );
  });

  test(
    'bare \$N vs timestamptz columns use PgDateTime or Type.timestampTz',
    () {
      // Column names that are timestamptz in Tentura schema and appear in
      // custom SQL compares/assigns. Keep narrow to avoid false positives.
      final columnOps = RegExp(
        r'\b('
        r'closes_at|opened_at|created_at|updated_at|expires_at|'
        r'available_at|lease_until|muted_until|emailed_at|seen_at|'
        r'last_seen_at|delivered_at|dead_lettered_at|snooze_until|'
        r'descendant_user_created_at|verified_at|revoked_at'
        r')\b'
        r'\s*(?:<|>|<=|>=|=)\s*'
        r'\$(\d+)\b'
        r'(?!\s*::)',
        caseSensitive: false,
      );

      final hits = <String>[];
      for (final file in dartFiles) {
        final text = file.readAsStringSync();
        for (final match in columnOps.allMatches(text)) {
          final param = match.group(2)!;
          final line = _lineNumber(text, match.start);
          // SQL already cast on the same line (e.g. `$1::timestamptz`) — skip.
          // Our regex uses negative lookahead for `::` immediately after $N;
          // also accept `$2::text::timestamptz` style via the lookahead.
          final windowStart = match.start;
          final windowEnd = (match.end + 400).clamp(0, text.length);
          final nearby = text.substring(windowStart, windowEnd);
          final hasSafeTypedBind = nearby.contains('PgDateTime') ||
              nearby.contains('Type.timestampTz') ||
              nearby.contains('PgTypes.timestampWithTimezone');
          if (!hasSafeTypedBind) {
            hits.add(
              '${file.path}:$line (column ${match.group(1)} vs \$$param '
              'without ::timestamptz cast or typed Variable nearby)',
            );
          }
        }
      }
      expect(
        hits,
        isEmpty,
        reason:
            'Bare \$N compared to timestamptz needs a typed Drift Variable '
            '(PgDateTime / Type.timestampTz) or an explicit \$N::timestamptz '
            'cast with an ISO string. Hits: $hits',
      );
    },
  );

  test(
    'attention_expiry lock query keeps typed timestamptz bind',
    () {
      final file = File(
        'lib/data/repository/attention_expiry_repository.dart',
      );
      final text = file.readAsStringSync();
      expect(text, contains('closes_at < \$1'));
      expect(
        text,
        contains('Variable(PgDateTime(now), PgTypes.timestampWithTimezone)'),
      );
      expect(text, isNot(contains('Variable<DateTime>')));
    },
  );
}

int _lineNumber(String text, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < text.length; i++) {
    if (text.codeUnitAt(i) == 0x0a) line++;
  }
  return line;
}
