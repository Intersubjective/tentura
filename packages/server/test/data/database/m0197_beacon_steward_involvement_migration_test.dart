import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

/// tentura-1ev: involvement SQL must recognise `beacon_steward` rows the way
/// content already does. Shipped as append-only migration `0197`.
void main() {
  test('m0197 is registered after m0196 in the migration chain', () {
    final versions = migrationsForTesting.map((m) => m.version).toList();
    expect(versions.indexOf('0196'), greaterThanOrEqualTo(0));
    expect(
      versions.indexOf('0197'),
      versions.indexOf('0196') + 1,
      reason: '0197 must follow 0196 without gaps',
    );
  });

  test('m0197 replaces beacon_can_read_involvement with a beacon_steward branch',
      () {
    final m0197 = migrationsForTesting.singleWhere(
      (m) => m.version == '0197',
      orElse: () => throw StateError('migration 0197 missing from registry'),
    );
    final sql = m0197.statements.join('\n');
    expect(sql, contains('beacon_can_read_involvement'));
    expect(sql, contains('beacon_steward'));
  });
}
