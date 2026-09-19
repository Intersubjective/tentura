@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

/// D17 — personal Request history. Cleared and settled receipts stay readable
/// for the Request they belong to, behind the same authorization wall
/// (`public.visible_attention_receipts`, m0117) every other attention read
/// uses, and behind the same `(createdAt, id)` cursor as `attentionFeed`.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_HISTORY_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_history',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attentionRequestHistory', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository query;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      query = AttentionRepository(database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.user_block,
  public.beacon_forward_edge,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_viewerId, _authorId, _strangerId]) {
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
VALUES
  (@ownedId, @viewerId, 'Owned', 'Owned request', 0),
  (@forwardedId, @authorId, 'Forwarded', 'Forwarded request', 0)
'''),
        parameters: {
          'ownedId': _ownedBeaconId,
          'forwardedId': _forwardedBeaconId,
          'viewerId': _viewerId,
          'authorId': _authorId,
        },
      );
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (id, beacon_id, sender_id, recipient_id)
VALUES ('Fattnhist01', @beaconId, @senderId, @recipientId)
'''),
        parameters: {
          'beaconId': _forwardedBeaconId,
          'senderId': _authorId,
          'recipientId': _viewerId,
        },
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test(
      'returns cleared and settled receipts for the Request, newest first',
      () async {
        // The whole point of D17: the rows a live feed has already stopped
        // showing are exactly the rows History exists to show.
        await _insertReceipt(
          writer,
          id: 'Nattnhistcleared',
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T10:00:00Z',
          clearedAt: '2026-07-17T10:00:00Z',
          clearReason: 'explicit',
        );
        await _insertReceipt(
          writer,
          id: 'Nattnhistsettled',
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T11:00:00Z',
          requiresAction: true,
          settlementKind: 'resolved',
          settledAt: '2026-07-18T10:00:00Z',
        );
        await _insertReceipt(
          writer,
          id: 'Nattnhistlive',
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T12:00:00Z',
        );

        final page = await query.attentionRequestHistory(
          accountId: _viewerId,
          beaconId: _ownedBeaconId,
        );

        expect(
          page.items.map((receipt) => receipt.id).toList(),
          ['Nattnhistlive', 'Nattnhistsettled', 'Nattnhistcleared'],
        );
        expect(page.nextCursor, isNull);
        final settled = page.items.firstWhere(
          (receipt) => receipt.id == 'Nattnhistsettled',
        );
        expect(settled.settlementKind, AttentionSettlementKind.resolved);
        expect(settled.isLiveObligation, isFalse);
      },
    );

    test('is scoped to one Request', () async {
      await _insertReceipt(
        writer,
        id: 'Nattnhistown',
        beaconId: _ownedBeaconId,
        createdAt: '2026-07-16T10:00:00Z',
      );
      await _insertReceipt(
        writer,
        id: 'Nattnhistfwd',
        beaconId: _forwardedBeaconId,
        createdAt: '2026-07-16T11:00:00Z',
      );

      final page = await query.attentionRequestHistory(
        accountId: _viewerId,
        beaconId: _ownedBeaconId,
      );

      expect(page.items.map((receipt) => receipt.id).toList(), [
        'Nattnhistown',
      ]);
    });

    test('a foreign account reads nothing of another account history', () async {
      await _insertReceipt(
        writer,
        id: 'Nattnhistprivate',
        beaconId: _ownedBeaconId,
        createdAt: '2026-07-16T10:00:00Z',
      );

      final page = await query.attentionRequestHistory(
        accountId: _strangerId,
        beaconId: _ownedBeaconId,
      );

      expect(page.items, isEmpty);
      expect(page.nextCursor, isNull);
    });

    test('a block hides history the viewer could otherwise read', () async {
      await _insertReceipt(
        writer,
        id: 'Nattnhistblocked',
        beaconId: _forwardedBeaconId,
        createdAt: '2026-07-16T10:00:00Z',
      );

      final before = await query.attentionRequestHistory(
        accountId: _viewerId,
        beaconId: _forwardedBeaconId,
      );
      expect(before.items.map((receipt) => receipt.id).toList(), [
        'Nattnhistblocked',
      ]);

      await writer.execute(
        Sql.named('''
INSERT INTO public.user_block (blocker_id, blocked_id, origin_id)
VALUES (@authorId, @viewerId, @authorId)
'''),
        parameters: {'authorId': _authorId, 'viewerId': _viewerId},
      );

      final after = await query.attentionRequestHistory(
        accountId: _viewerId,
        beaconId: _forwardedBeaconId,
      );
      expect(after.items, isEmpty);
    });

    test(
      'pages on the feed cursor without duplicates or gaps, and stays stable '
      'when a newer row arrives between pages',
      () async {
        for (var index = 1; index <= 5; index++) {
          await _insertReceipt(
            writer,
            id: 'Nattnhistpage$index',
            beaconId: _ownedBeaconId,
            createdAt: '2026-07-16T1$index:00:00Z',
          );
        }

        final first = await query.attentionRequestHistory(
          accountId: _viewerId,
          beaconId: _ownedBeaconId,
          limit: 2,
        );
        expect(first.items.map((receipt) => receipt.id).toList(), [
          'Nattnhistpage5',
          'Nattnhistpage4',
        ]);
        expect(first.nextCursor, isNotNull);
        expect(first.nextCursor!.id, 'Nattnhistpage4');

        // A newer receipt lands after the first page was served. A newest-first
        // cursor must neither surface it late nor shift the remaining rows.
        await _insertReceipt(
          writer,
          id: 'Nattnhistpage9',
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T23:00:00Z',
        );

        final second = await query.attentionRequestHistory(
          accountId: _viewerId,
          beaconId: _ownedBeaconId,
          cursor: first.nextCursor,
          limit: 2,
        );
        expect(second.items.map((receipt) => receipt.id).toList(), [
          'Nattnhistpage3',
          'Nattnhistpage2',
        ]);

        final third = await query.attentionRequestHistory(
          accountId: _viewerId,
          beaconId: _ownedBeaconId,
          cursor: second.nextCursor,
          limit: 2,
        );
        expect(third.items.map((receipt) => receipt.id).toList(), [
          'Nattnhistpage1',
        ]);
        expect(third.nextCursor, isNull);

        final seen = [
          ...first.items,
          ...second.items,
          ...third.items,
        ].map((receipt) => receipt.id).toList();
        expect(seen.toSet(), hasLength(seen.length), reason: 'no duplicates');
        expect(seen, [
          'Nattnhistpage5',
          'Nattnhistpage4',
          'Nattnhistpage3',
          'Nattnhistpage2',
          'Nattnhistpage1',
        ]);
      },
    );

    test('ties on created_at break by descending id, like the feed', () async {
      for (final id in ['Nattnhistties1', 'Nattnhistties2', 'Nattnhistties3']) {
        await _insertReceipt(
          writer,
          id: id,
          beaconId: _ownedBeaconId,
          createdAt: '2026-07-16T10:00:00Z',
        );
      }

      final first = await query.attentionRequestHistory(
        accountId: _viewerId,
        beaconId: _ownedBeaconId,
        limit: 2,
      );
      final second = await query.attentionRequestHistory(
        accountId: _viewerId,
        beaconId: _ownedBeaconId,
        cursor: first.nextCursor,
        limit: 2,
      );

      expect(
        [...first.items, ...second.items].map((receipt) => receipt.id).toList(),
        ['Nattnhistties3', 'Nattnhistties2', 'Nattnhistties1'],
      );
    });
  }, skip: skipReason);
}

const _viewerId = 'Uattnhist01';
const _authorId = 'Uattnhist02';
const _strangerId = 'Uattnhist03';
const _ownedBeaconId = 'Battnhistown';
const _forwardedBeaconId = 'Battnhistfwd';

Future<void> _insertReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  required String createdAt,
  bool requiresAction = false,
  String? settlementKind,
  String? settledAt,
  String? clearedAt,
  String? clearReason,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy,
  requires_action, attention_thread_key,
  settlement_kind, settled_at, cleared_at, clear_reason
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  @requiresAction, @threadKey,
  @settlementKind, CAST(@settledAt AS timestamptz),
  CAST(@clearedAt AS timestamptz), @clearReason
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'requiresAction': requiresAction,
    'threadKey': requiresAction ? 'v1|needsMe|$id|$_viewerId' : null,
    'settlementKind': settlementKind,
    'settledAt': settledAt,
    'clearedAt': clearedAt,
    'clearReason': clearReason,
  },
);
