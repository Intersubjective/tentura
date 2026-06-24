import 'dart:io';

import 'package:test/test.dart';

void main() {
  late String migrationSource;

  setUp(() {
    migrationSource = File(
      'lib/data/database/migration/m0100.dart',
    ).readAsStringSync();
  });

  test('m0100 dedup SQL cancels duplicates and adds partial unique index', () {
    expect(migrationSource, contains('cancelled_at = now()'));
    expect(migrationSource, contains('k.beacon_id = e.beacon_id'));
    expect(migrationSource, contains('bfe_active_unique'));
    expect(
      migrationSource,
      contains(
        'ON public.beacon_forward_edge (beacon_id, sender_id, recipient_id)',
      ),
    );
    expect(migrationSource, contains('WHERE cancelled_at IS NULL'));
  });

  test('m0100 provenance excludes cancelled forward edges', () {
    expect(migrationSource, contains('AND bfe.cancelled_at IS NULL'));
    expect(
      migrationSource,
      contains('inbox_item_inbox_provenance_data'),
    );
  });
}
