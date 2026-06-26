import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String migrationSource;

  setUp(() {
    migrationSource = File(
      'lib/data/database/migration/m0103.dart',
    ).readAsStringSync();
  });

  test('m0103 provenance excludes self and null-context invite edges', () {
    expect(migrationSource, contains('bfe.sender_id <> inbox_row.user_id'));
    expect(
      migrationSource,
      contains("nullif(trim(bfe.context), '') IS NULL"),
    );
    expect(migrationSource, contains('AND bfe.cancelled_at IS NULL'));
  });
}
