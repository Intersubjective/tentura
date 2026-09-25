@Tags(['pg'])
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';
import 'package:tentura_server/data/database/migration/_migrations.dart';

import '../../support/disposable_pg_target.dart';
import '../../support/pg_test_public_keys.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_BRIDGE_PEOPLE_SEEN_PLAN_PG_TEST_DB',
    defaultNamePrefix: 'tentura_test_brdgpeopleplan',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable bridge_attention_people_seen plan PG test';

  group('bridge_attention_people_seen UPDATE plan', () {
    late Connection writer;

    const authorId = 'Upsplnauthor';
    const stewardId = 'Upsplnsteward';
    const targetBeaconId = 'Bpsplntarget';
    final watermarkAt = DateTime.utc(2026, 8, 1, 18);

    setUpAll(() async {
      if (skipReason != false) return;
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);

      for (final (id, slot) in [(authorId, 1), (stewardId, 2)]) {
        await writer.execute(
          Sql.named(r'''
INSERT INTO public."user" (id, display_name, public_key, created_at, updated_at)
VALUES (@id, @id, @publicKey, '2026-01-01T00:00:00Z', '2026-01-01T00:00:00Z')
'''),
          parameters: {
            'id': id,
            'publicKey': pgTestPublicKey('pspln', slot),
          },
        );
      }

      for (var i = 0; i <= 9; i++) {
        await writer.execute(
          Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @ownerId, 'Fixture', 'Fixture', 0)
'''),
          parameters: {
            'id': i == 0 ? targetBeaconId : 'Bpsplnnoise$i',
            'ownerId': authorId,
          },
        );
      }
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await writer.close();
      await target.drop();
    });

    Future<void> seedReceipts({
      required String accountId,
      required String shape,
      required bool requiresAction,
    }) async {
      for (var i = 0; i < 200; i++) {
        final id = 'Npspln${shape}${i.toString().padLeft(3, '0')}';
        final beaconId = i < 20 ? targetBeaconId : 'Bpsplnnoise${(i % 9) + 1}';
        await writer.execute(
          Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority, title, body, action_url,
  dedup_key, created_at, beacon_id, source_event_key, destination_kind,
  presentation_key, presentation_payload, suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  @id, @accountId, @category, @kind, 'normal', 'Offer', 'Body', '/attention',
  @dedupKey, @createdAt, @beaconId, @sourceEventKey, 'beacon_people_offer',
  'help_offer_submitted', '{"eventType":"fixture"}'::jsonb, 'standard',
  'beacon_content', @requiresAction, @threadKey
)
'''),
          parameters: {
            'id': id,
            'accountId': accountId,
            'category': requiresAction ? 'asksOfMe' : 'coordination',
            'kind': requiresAction ? 'needsMe' : 'coordinationChanged',
            'dedupKey': 'dedup-$id',
            'createdAt': watermarkAt.subtract(const Duration(hours: 1)),
            'beaconId': beaconId,
            'sourceEventKey': 'source-$id',
            'requiresAction': requiresAction,
            'threadKey': requiresAction ? 'v1|needsMe|$id|$accountId' : null,
          },
        );
      }
      await writer.execute('ANALYZE public.notification_outbox');
    }

    Future<String> explainBridge(String accountId) async {
      await writer.execute('SET enable_seqscan = off');
      final rows = await writer.execute(
        Sql.named('''
EXPLAIN (COSTS OFF)
UPDATE public.notification_outbox n
SET seen_at = COALESCE(n.seen_at, now())
WHERE n.account_id = @accountId
  AND n.beacon_id = @beaconId
  AND n.destination_kind = 'beacon_people_offer'
  AND n.presentation_key = 'help_offer_submitted'
  AND n.created_at <= @lastSeenAt
  AND n.seen_at IS NULL
'''),
        parameters: {
          'accountId': accountId,
          'beaconId': targetBeaconId,
          'lastSeenAt': watermarkAt,
        },
      );
      return rows.map((row) => row.single).join('\n');
    }

    void expectOutboxIndexPlan(String plan, String shape) {
      expect(
        plan,
        isNot(
          matches(RegExp(r'Seq Scan on (?:public\.)?notification_outbox\b')),
        ),
        reason: '$shape bridge UPDATE plan:\n$plan',
      );
      final indexScan = RegExp(
        r'Index Scan using \S+ on (?:public\.)?notification_outbox\b',
      ).hasMatch(plan);
      final bitmapIndexScan =
          RegExp(
            r'Bitmap Heap Scan on (?:public\.)?notification_outbox\b',
          ).hasMatch(plan) &&
          RegExp(r'Bitmap Index Scan on \S+').hasMatch(plan);
      expect(
        indexScan || bitmapIndexScan,
        isTrue,
        reason: '$shape bridge UPDATE must use an outbox index:\n$plan',
      );
    }

    test('author obligation receipts use an outbox index', () async {
      await seedReceipts(
        accountId: authorId,
        shape: 'auth',
        requiresAction: true,
      );
      expectOutboxIndexPlan(await explainBridge(authorId), 'author');
    }, skip: skipReason);

    test('steward optional receipts use an outbox index', () async {
      await seedReceipts(
        accountId: stewardId,
        shape: 'stew',
        requiresAction: false,
      );
      expectOutboxIndexPlan(await explainBridge(stewardId), 'steward');
    }, skip: skipReason);
  });

  test('P1.6 journal records the measured index decision and rationale', () {
    final journal = File(
      '../../docs/plans/issue-178-help-offer-author-seen-implementation-journal.md',
    ).readAsStringSync();
    final heading = journal.indexOf('## P1.6');
    final nextHeading = heading < 0
        ? -1
        : journal.indexOf('\n## ', heading + 2);
    final section = heading < 0
        ? null
        : journal.substring(
            heading,
            nextHeading < 0 ? journal.length : nextHeading,
          );

    expect(
      section,
      isNotNull,
      reason: 'Record the P1.6 measurement in the implementation journal.',
    );
    expect(section, contains('author'));
    expect(section, contains('steward'));
    final journalSection = section!;
    final decision = RegExp(
      r'\*\*Decision:\s*(index added|no index added)\.?\*\*',
      caseSensitive: false,
    ).firstMatch(journalSection);
    expect(
      decision,
      isNotNull,
      reason: 'State explicitly whether P1.6 added an outbox index.',
    );

    final rationale = RegExp(
      r'\*\*Rationale:\*\*\s*([^\n]+)',
      caseSensitive: false,
    ).firstMatch(journalSection);
    expect(
      rationale,
      isNotNull,
      reason:
          'State why the measured author and steward plans support the decision.',
    );
    final rationaleText = rationale!.group(1)!;
    expect(rationaleText, contains('author'));
    expect(rationaleText, contains('steward'));
    final expectedScan = decision!.group(1)!.toLowerCase() == 'index added'
        ? RegExp(r'Seq Scan', caseSensitive: false)
        : RegExp(r'(?:Bitmap )?Index Scan', caseSensitive: false);
    expect(
      rationaleText,
      matches(expectedScan),
      reason: 'Connect the index decision to both measured outbox plans.',
    );
  });
}
