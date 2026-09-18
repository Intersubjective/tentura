@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';

/// U05a — `m0179`: the collapse-keyed outbox index stops being UNIQUE.
///
/// The constraint *state* is proven by writes, not by reading the catalogue:
/// a shape the schema must still reject and a shape it must now permit. The
/// index definition is asserted too, but only as a second witness.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U05A_INDEX_TEST_DB',
    defaultNamePrefix: 'tentura_test_u05a_index',
  );
  final upgradeTarget = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_U05A_INDEX_UPGRADE_TEST_DB',
    defaultNamePrefix: 'tentura_test_u05a_index_upgrade',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('m0179 on a fully migrated database', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session);
    });

    setUp(() async {
      await _resetFixtures(writer);
    });

    test('keeps the collapse lookup index, without uniqueness', () async {
      final rows = await writer.execute('''
SELECT pg_get_indexdef(i.indexrelid), i.indisunique,
       pg_get_expr(i.indpred, i.indrelid)
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE i.indrelid = 'public.notification_outbox'::regclass
  AND c.relname = 'notification_outbox__dedup'
''');
      expect(rows, hasLength(1), reason: 'the lookup index must survive');
      expect(rows.single[0]! as String, startsWith('CREATE INDEX'));
      expect(rows.single[1], false);
      expect(rows.single[2], '(seen_at IS NULL)');
    });

    test('permits two unseen receipts in one collapse family', () async {
      await _insertReceipt(writer, id: 'Nu05a1', occurrenceId: 'Ou05a1');
      await _insertReceipt(writer, id: 'Nu05a2', occurrenceId: 'Ou05a2');

      final rows = await writer.execute('''
SELECT count(*)::int FROM public.notification_outbox
WHERE dedup_key = '$_dedupKey' AND seen_at IS NULL
''');
      expect(rows.single.single, 2);
    });

    test(
      'still rejects a second receipt for one (occurrence_id, account_id)',
      () async {
        await _insertReceipt(writer, id: 'Nu05a3', occurrenceId: 'Ou05a3');
        await expectLater(
          _insertReceipt(writer, id: 'Nu05a4', occurrenceId: 'Ou05a3'),
          throwsA(
            isA<ServerException>().having(
              (error) => '${error.code} ${error.message}',
              'unique violation naming the identity index',
              allOf(
                contains('23505'),
                contains('notification_outbox__occurrence_account'),
              ),
            ),
          ),
        );
      },
    );

    test('re-applying every m0179 statement is a no-op', () async {
      final statements = migrationsForTesting
          .firstWhere((migration) => migration.version == '0179')
          .statements;
      for (var pass = 0; pass < 2; pass++) {
        for (final statement in statements) {
          await writer.execute(statement);
        }
      }

      final rows = await writer.execute('''
SELECT count(*)::int, bool_or(i.indisunique)
FROM pg_index i
JOIN pg_class c ON c.oid = i.indexrelid
WHERE i.indrelid = 'public.notification_outbox'::regclass
  AND c.relname = 'notification_outbox__dedup'
''');
      expect(rows.single, [1, false]);
    });
  }, skip: skipReason);

  group('m0179 upgrade path from 0178', () {
    late DisposablePgWriterSession session;
    late Connection writer;

    setUpAll(() async {
      if (skipReason != false) return;
      session = await setUpDisposablePgWriter(
        target: upgradeTarget,
        lastInclusiveVersion: '0178',
      );
      writer = session.writer;
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await tearDownDisposablePgWriter(session: session);
    });

    test('the pre-U05a schema rejects the second unseen receipt', () async {
      await _resetFixtures(writer);
      await _insertReceipt(writer, id: 'Nu05aold1', occurrenceId: 'Ou05aold1');
      await expectLater(
        _insertReceipt(writer, id: 'Nu05aold2', occurrenceId: 'Ou05aold2'),
        throwsA(
          isA<ServerException>().having(
            (error) => '${error.code} ${error.message}',
            'unique violation naming the collapse index',
            allOf(
              contains('23505'),
              contains('notification_outbox__dedup'),
            ),
          ),
        ),
        reason:
            'this is the gate U05a removes; if it stops failing here, m0179 '
            'is being applied too early and the test proves nothing',
      );
    });

    test('applying m0179 lets the same pair of writes through', () async {
      await migrateDbSchemaThrough(writer, '0179');
      await _resetFixtures(writer);
      await _insertReceipt(writer, id: 'Nu05anew1', occurrenceId: 'Ou05anew1');
      await _insertReceipt(writer, id: 'Nu05anew2', occurrenceId: 'Ou05anew2');

      final rows = await writer.execute('''
SELECT count(*)::int FROM public.notification_outbox
WHERE dedup_key = '$_dedupKey'
''');
      expect(rows.single.single, 2);
    });
  }, skip: skipReason);
}

const _accountId = 'Uu05aindex';
const _dedupKey = '$_accountId|attention-v1|relay|Bu05aindex';

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String occurrenceId,
}) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.attention_occurrence (
  id, source_event_key, event_type, actor_user_id, immutable_payload
) VALUES (@occurrenceId, @occurrenceId, 'relayReceived', @accountId, '{}'::jsonb)
ON CONFLICT (id) DO NOTHING
'''),
    parameters: {'occurrenceId': occurrenceId, 'accountId': _accountId},
  );
  await writer.execute(
    Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, source_event_key, occurrence_id, destination_kind,
  target_entity_id, presentation_key, presentation_payload,
  suppression_class, access_policy, requires_action
) VALUES (
  @id, @accountId, 'coordination', 'newRelay', 'normal',
  'Forwarded Request', 'A Request was forwarded to you', '/#/view',
  @dedupKey, @occurrenceId, @occurrenceId, 'profile', @accountId,
  'relationship_formed', '{}'::jsonb, 'standard', 'profile', false
)
'''),
    parameters: {
      'id': id,
      'accountId': _accountId,
      'dedupKey': _dedupKey,
      'occurrenceId': occurrenceId,
    },
  );
}

Future<void> _resetFixtures(Connection writer) async {
  await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.attention_occurrence,
  public."user"
CASCADE
''');
  await writer.execute(
    Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, 'u05a-index-key')
'''),
    parameters: {'id': _accountId},
  );
}
