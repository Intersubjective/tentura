@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/migration/_migrations.dart';
import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

/// #601 (option B, decided 2026-10-22) — the server half of "Mark unread on
/// a cleared Updates item restores it under Unread".
///
/// The Unread view and `unreadTotal` are the CLEAR axis
/// (`NOT requires_action AND cleared_at IS NULL`), so `markUnseen`, which
/// only nulls `seen_at`, leaves a cleared row off Unread (pinned in
/// attention_active_attention_axis_pg_test.dart, and still true). The new
/// `AttentionAckRepository.markUnread` resets the clear facts the
/// `notification_outbox__clear_facts_chk` CHECK ties together (`cleared_at`,
/// `clear_reason`, `cleared_by_operation_id`) and the read axis, for the
/// caller's own visible optional receipts only. No schema change: existing
/// columns go back to NULL.
///
/// pg only (no MeritRank), so it runs locally.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_MARK_UNREAD_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_mark_unread',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('#601 markUnread un-clears', () {
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository query;
    late AttentionAckRepository ack;

    setUpAll(() async {
      if (skipReason != false) return;
      await target.recreate();
      writer = await Connection.open(
        target.databaseEnv.pgEndpoint,
        settings: target.databaseEnv.pgEndpointSettings,
      );
      await writer.execute('SET check_function_bodies = false');
      await migrateDbSchema(writer);
      database = TenturaDb(target.databaseEnv);
      query = AttentionRepository(database);
      ack = AttentionAckRepository(database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_viewerId, _otherId]) {
        await writer.execute(
          Sql.named('''
INSERT INTO public."user" (id, display_name, public_key)
VALUES (@id, @id, @key)
'''),
          parameters: {'id': id, 'key': '$id-key'},
        );
      }
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@hiddenId, @otherId, 'Hidden', 'Hidden request', 0)
'''),
        parameters: {'hiddenId': _hiddenBeaconId, 'otherId': _otherId},
      );
    });

    tearDownAll(() async {
      if (skipReason != false) return;
      await database.close();
      await writer.close();
      await target.drop();
    });

    test('a cleared and read receipt comes back under Unread', () async {
      await _insertReceipt(
        writer,
        id: 'Ncleared',
        seenAt: _at,
        clearedAt: _at,
      );
      await _insertReceipt(writer, id: 'Nactive');

      final before = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
      );
      expect(
        before.page.items.map((r) => r.id),
        ['Nactive'],
        reason: 'precondition: the cleared row is off Unread',
      );

      expect(
        await ack.markUnread(accountId: _viewerId, ids: const ['Ncleared']),
        1,
      );

      final row = await _row(writer, 'Ncleared');
      expect(row.clearedAt, isNull, reason: 'the clear axis is reset');
      expect(row.clearReason, isNull);
      expect(row.clearedByOperationId, isNull);
      expect(row.seenAt, isNull, reason: 'and it reads as unread again');

      final after = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
      );
      expect(
        after.page.items.map((r) => r.id),
        containsAll(<String>['Ncleared', 'Nactive']),
      );
      expect(after.summary.unreadTotal, 2);

      expect(
        await ack.markUnread(accountId: _viewerId, ids: const ['Ncleared']),
        0,
        reason: 'a second Mark unread has nothing left to change',
      );
    });

    test('a cleared but never-read receipt is un-cleared too', () async {
      await _insertReceipt(writer, id: 'Nswept', clearedAt: _at);

      expect(
        await ack.markUnread(accountId: _viewerId, ids: const ['Nswept']),
        1,
      );
      final row = await _row(writer, 'Nswept');
      expect(row.clearedAt, isNull);
      expect(row.clearReason, isNull);
    });

    test("guard: another account's receipt is not touched", () async {
      await _insertReceipt(
        writer,
        id: 'Nforeign',
        accountId: _otherId,
        seenAt: _at,
        clearedAt: _at,
      );

      expect(
        await ack.markUnread(accountId: _viewerId, ids: const ['Nforeign']),
        0,
      );
      final row = await _row(writer, 'Nforeign');
      expect(row.clearedAt, isNotNull);
      expect(row.seenAt, isNotNull);
    });

    test('guard: a receipt the caller may no longer read stays cleared',
        () async {
      await _insertReceipt(
        writer,
        id: 'Nhidden',
        beaconId: _hiddenBeaconId,
        accessPolicy: 'beacon_content',
        destinationKind: 'beacon',
        presentationKey: 'request_status_changed',
        seenAt: _at,
        clearedAt: _at,
      );

      expect(
        await ack.markUnread(accountId: _viewerId, ids: const ['Nhidden']),
        0,
      );
      expect((await _row(writer, 'Nhidden')).clearedAt, isNotNull);
    });

    test(
      'an unseen sibling sharing the same dedup_key does not block un-clear',
      () async {
        // notification_outbox__dedup is a plain (non-unique) index, and in
        // production dedup_key is collapse-family derived, so siblings share
        // it. A markUnread that copies the markUnseen NOT EXISTS (unseen
        // sibling) guard into its WHERE would skip this row and leave it
        // cleared. Un-clear must not depend on siblings.
        await _insertReceipt(
          writer,
          id: 'NclearedFamily',
          seenAt: _at,
          clearedAt: _at,
          dedupKey: 'family-shared',
        );
        await _insertReceipt(
          writer,
          id: 'NunseenFamily',
          dedupKey: 'family-shared',
        );

        expect(
          await ack.markUnread(
            accountId: _viewerId,
            ids: const ['NclearedFamily'],
          ),
          greaterThanOrEqualTo(1),
        );

        final row = await _row(writer, 'NclearedFamily');
        expect(row.clearedAt, isNull, reason: 'un-cleared despite sibling');
        expect(row.clearReason, isNull);
        expect(row.clearedByOperationId, isNull);

        final after = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.unread,
        );
        expect(
          after.page.items.map((r) => r.id),
          contains('NclearedFamily'),
        );
      },
    );

    test('guard: only the named receipt is un-cleared', () async {
      await _insertReceipt(
        writer,
        id: 'Ntarget',
        seenAt: _at,
        clearedAt: _at,
      );
      await _insertReceipt(
        writer,
        id: 'Nsibling',
        seenAt: _at,
        clearedAt: _at,
      );

      await ack.markUnread(accountId: _viewerId, ids: const ['Ntarget']);

      final sibling = await _row(writer, 'Nsibling');
      expect(sibling.clearedAt, isNotNull);
      expect(sibling.seenAt, isNotNull);
    });
  }, skip: skipReason);
}

const _viewerId = 'Umarkunread01';
const _otherId = 'Umarkunread02';
const _hiddenBeaconId = 'Bmarkunreadhidden';
const _at = '2026-10-20T12:00:00Z';

typedef _Row = ({
  Object? seenAt,
  Object? clearedAt,
  Object? clearReason,
  Object? clearedByOperationId,
});

Future<_Row> _row(Connection writer, String id) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT seen_at, cleared_at, clear_reason, cleared_by_operation_id
FROM public.notification_outbox
WHERE id = @id
'''),
    parameters: {'id': id},
  );
  final row = rows.single;
  return (
    seenAt: row[0],
    clearedAt: row[1],
    clearReason: row[2],
    clearedByOperationId: row[3],
  );
}

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  String accountId = _viewerId,
  String? beaconId,
  String accessPolicy = 'profile',
  String destinationKind = 'profile',
  String presentationKey = 'invite_accepted',
  String? seenAt,
  String? clearedAt,
  String? dedupKey,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  cleared_at, clear_reason,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST('2026-10-20T10:00:00Z' AS timestamptz),
  CAST(@seenAt AS timestamptz),
  CAST(@clearedAt AS timestamptz),
  @clearReason,
  @beaconId, @sourceEventKey,
  @destinationKind, @presentationKey, '{"eventType":"fixture"}'::jsonb,
  'standard', @accessPolicy
)
'''),
  parameters: {
    'id': id,
    'accountId': accountId,
    'dedupKey': dedupKey ?? 'dedup-$id',
    'seenAt': seenAt,
    'clearedAt': clearedAt,
    'clearReason': clearedAt == null ? null : 'explicit',
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'destinationKind': destinationKind,
    'presentationKey': presentationKey,
    'accessPolicy': accessPolicy,
  },
);
