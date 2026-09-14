import 'package:drift_postgres/drift_postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/repository/constellation_field_repository.dart';

void main() {
  group('readCustomSelectTimestamptz', () {
    test(
      'parses Drift DateTime.toString midnight UTC without int.parse',
      () {
        // Drift's read<DateTime> int.parse()s this wire form as unix seconds
        // and throws: FormatException: Invalid radix-10 number (at character 1)
        const wire = '2026-05-18 00:00:00.000Z';
        expect(
          readCustomSelectTimestamptz(wire),
          DateTime.utc(2026, 5, 18),
        );
      },
    );

    test('parses ISO-8601 with T separator', () {
      expect(
        readCustomSelectTimestamptz('2026-05-18T00:00:00.000Z'),
        DateTime.utc(2026, 5, 18),
      );
    });

    test('passes through DateTime and PgDateTime', () {
      final utc = DateTime.utc(2026, 5, 18, 12);
      expect(readCustomSelectTimestamptz(utc), utc);
      expect(readCustomSelectTimestamptz(PgDateTime(utc)), utc);
    });

    test('returns null for null', () {
      expect(readCustomSelectTimestamptz(null), isNull);
    });
  });
}
