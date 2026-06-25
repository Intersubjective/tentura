import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String migrationSource;

  setUp(() {
    migrationSource = File(
      'lib/data/database/migration/m0089.dart',
    ).readAsStringSync();
  });

  test('m0089 backfill SQL is idempotent on type 15 and published states', () {
    expect(migrationSource, contains('type = 15'));
    expect(migrationSource, contains('state NOT IN (2, 3)'));
    expect(migrationSource, contains('NOT EXISTS'));
    expect(migrationSource, contains('b.created_at'));
    expect(migrationSource, contains('beaconPublished'));
  });
}
