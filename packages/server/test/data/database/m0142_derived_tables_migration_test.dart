@Tags(['pg'])
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_M0142_MIGRATION_TEST_DB',
    defaultNamePrefix: 'tentura_test_m0142',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  Future<void> migrateLocked(Connection connection) async {
    await withDisposablePgLifecycleLock(
      target.adminEnv,
      () => migrateDbSchema(connection),
    );
  }

  group('m0142 derived tables and context normalization', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      if (skipReason != false) {
        return;
      }
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    tearDownAll(() async {
      if (skipReason != false) {
        return;
      }
      await tearDownDisposablePgWriter(session: session);
    });

    test(
      'fresh schema creates all A2 tables, indexes, and singleton epoch row',
      () async {
        await migrateLocked(writer);
        await _expectA2Schema(writer);
      },
      skip: skipReason,
    );

  });
}

Future<void> _expectA2Schema(Connection writer) async {
  final tables = await writer.execute(r'''
SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'public'
  AND table_name IN (
    'capability_evidence_edge',
    'capability_evidence_generation',
    'ego_witness_window',
    'capability_routing_mute',
    'mr_publish_epoch'
  )
ORDER BY table_name
''');
  expect(
    tables.map((r) => r[0]).toList(),
    [
      'capability_evidence_edge',
      'capability_evidence_generation',
      'capability_routing_mute',
      'ego_witness_window',
      'mr_publish_epoch',
    ],
  );

  final indexes = await writer.execute(r'''
SELECT indexname
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname IN (
    'cee_projection_idx',
    'cee_expiry_idx',
    'eww_gc_idx'
  )
ORDER BY indexname
''');
  expect(
    indexes.map((r) => r[0]).toList(),
    ['cee_expiry_idx', 'cee_projection_idx', 'eww_gc_idx'],
  );

  final selfCheck = await writer.execute(r'''
SELECT conname
FROM pg_constraint
WHERE conname = 'cee_no_self'
''');
  expect(selfCheck, hasLength(1));

  final epochRows = await writer.execute(r'''
SELECT id, epoch
FROM public.mr_publish_epoch
ORDER BY id
''');
  expect(epochRows, hasLength(1));
  expect(epochRows.single[0], true);
  expect(epochRows.single[1], 0);
}

Future<void> _seedFixture(Connection writer) async {
  await writer.execute(r'''
INSERT INTO public."user" (id, display_name, public_key)
VALUES
  ('Um0142obs1', 'Observer', 'pk-obs'),
  ('Um0142sub1', 'Subject', 'pk-sub'),
  ('Um0142user1', 'Self', 'pk-self')
ON CONFLICT DO NOTHING
''');
}

