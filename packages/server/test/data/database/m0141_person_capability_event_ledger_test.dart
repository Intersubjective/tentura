@Tags(['pg'])
library;

import 'dart:io';

import 'package:injectable/injectable.dart' show Environment;
import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/env.dart';

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

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Upcem0141obs1', 'Observer', 'pk-obs'),
  ('Upcem0141sub1', 'Subject', 'pk-sub'),
  ('Upcem0141auth1', 'Author', 'pk-auth')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon (id, user_id, title, description)
VALUES ('Bpcem0141bcn1', 'Upcem0141auth1', 'Beacon', 'd')
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at
) VALUES (
  'Fpcem0141edge1', 'Bpcem0141bcn1', 'Upcem0141obs1', 'Upcem0141sub1', now()
)
ON CONFLICT DO NOTHING
''');

  await writer.execute(r'''
INSERT INTO public.invitation (id, user_id, created_at, updated_at)
VALUES ('Ipcem0141inv1', 'Upcem0141obs1', now(), now())
ON CONFLICT DO NOTHING
''');
}

