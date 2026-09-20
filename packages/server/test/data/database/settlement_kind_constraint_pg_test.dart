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
    envVarName: 'TENTURA_SETTLEMENT_KIND_CONSTRAINT_TEST_DB',
    defaultNamePrefix: 'tentura_test_settle_kind',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('notification_outbox__settlement_kind_chk expired admission', () {
    // The pre-0166 half of this group tested that `expired` was rejected
    // before the constraint was widened. That schema is inside the squashed
    // baseline and is no longer reachable; what still has to hold is that the
    // constraint admits `expired` at head.
    test('settling an obligation as expired is accepted', () async {
      await target.recreate();
      final writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      try {
        await writer.execute('SET check_function_bodies = false');
        await migrateDbSchema(writer);
        await _seedUser(writer);
        await _insertUnsettledObligation(writer, receiptId: 'Nexp0166');

        await writer.execute('''
UPDATE public.notification_outbox
SET
  settlement_kind = 'expired',
  settled_at = '2026-07-18T12:00:00Z'::timestamptz
WHERE id = 'Nexp0166'
''');

        final rows = await writer.execute('''
SELECT settlement_kind, settled_at IS NOT NULL
FROM public.notification_outbox
WHERE id = 'Nexp0166'
''');
        expect(rows.single[0], 'expired');
        expect(rows.single[1], isTrue);

        final checkRows = await writer.execute('''
SELECT pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.notification_outbox'::regclass
  AND conname = 'notification_outbox__settlement_kind_chk'
''');
        expect(checkRows.single[0], contains('expired'));
      } finally {
        await writer.close();
        await target.drop();
      }
    }, skip: skipReason);
  }, skip: skipReason);
}

Future<void> _seedUser(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE public.notification_outbox, public."user" CASCADE
''');
  await writer.execute('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES ('Uexp20', 'Expired settlement', 'expired-settlement-public-key')
''');
}

Future<void> _insertUnsettledObligation(
  Connection writer, {
  required String receiptId,
}) async {
  await writer.execute('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  '$receiptId', 'Uexp20', 'asksOfMe', 'needsMe', 'normal',
  'Obligation', 'Obligation body', '/attention', 'dedup-$receiptId',
  '2026-07-16T12:00:00Z'::timestamptz,
  'Bexp20', 'source-$receiptId',
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  true, 'v1|needsMe|$receiptId|Uexp20'
)
''');
}

