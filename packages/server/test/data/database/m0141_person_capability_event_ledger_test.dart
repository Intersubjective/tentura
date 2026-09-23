@Tags(['pg'])
library;


import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0141_MIGRATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0141',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('m0141 person_capability_event ledger extension', () {
    late Connection writer;

    setUpAll(() async {
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
    });

    tearDownAll(() async {
      await writer.close();
      await target.drop();
    });

    test(
      'fresh schema gains provenance columns, CHECK, and indexes',
      () async {
        await migrateDbSchema(writer);

        final columns = await writer.execute(r'''
SELECT column_name, is_nullable
FROM information_schema.columns
WHERE table_schema = 'public'
  AND table_name = 'person_capability_event'
  AND column_name IN ('forward_edge_id', 'invitation_id')
ORDER BY column_name
''');
        expect(
          columns.map((r) => [r[0], r[1]]).toList(),
          [
            ['forward_edge_id', 'YES'],
            ['invitation_id', 'YES'],
          ],
        );

        final constraints = await writer.execute(r'''
SELECT conname
FROM pg_constraint
WHERE conname = 'pce_source_type_ck'
''');
        expect(constraints, hasLength(1));

        final indexes = await writer.execute(r'''
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'pce_seed_attestation_uq',
    'pce_forward_reason_uq',
    'pce_close_ack_uq',
    'pce_aggregation_idx'
  )
ORDER BY indexname
''');
        expect(
          indexes.map((r) => r[0]).toList(),
          [
            'pce_aggregation_idx',
            'pce_close_ack_uq',
            'pce_forward_reason_uq',
            'pce_seed_attestation_uq',
          ],
        );
      },
      skip: skipReason,
    );

  });
}


