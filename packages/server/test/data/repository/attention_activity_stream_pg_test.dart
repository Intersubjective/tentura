@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_ACTIVITY_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_activity',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('activity stream forwards and watching digest', () {
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
  public.beacon_help_offer,
  public.inbox_item,
  public.beacon_forward_edge,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_viewerId, _authorId]) {
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
  (@foreignId, @authorId, 'Foreign', 'Foreign request', 0),
  (@closedId, @authorId, 'Closed', 'Closed request', 1),
  (@deletedId, @authorId, 'Deleted', 'Deleted request', 2)
'''),
        parameters: {
          'ownedId': _ownedBeaconId,
          'foreignId': _foreignBeaconId,
          'closedId': _closedBeaconId,
          'deletedId': _deletedBeaconId,
          'viewerId': _viewerId,
          'authorId': _authorId,
        },
      );
      await _ensureForwardPath(writer, beaconId: _foreignBeaconId);
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test('open forward is absent from the activity page', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 0,
        latestForwardAt: '2026-08-01T12:00:00Z',
      );
      await _insertRelayReceipt(
        writer,
        id: 'Nactopen01',
        beaconId: _foreignBeaconId,
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(
        feed.page.items.where((item) => item.itemKind == AttentionItemKind.forward),
        isEmpty,
      );
      expect(
        feed.page.items.where((item) => item.id == 'Nactopen01'),
        isEmpty,
      );
    });

    test('watching produces one forward item at latest_forward_at', () async {
      const at = '2026-08-02T14:30:00Z';
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 1,
        latestForwardAt: at,
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final forward = feed.page.items.single;
      expect(forward.itemKind, AttentionItemKind.forward);
      expect(forward.id, 'inbox:$_foreignBeaconId');
      expect(forward.forwardOutcome, 'watching');
      expect(forward.createdAt, DateTime.parse(at).toUtc());
    });

    test('reject produces notInterested forward outcome', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 2,
        latestForwardAt: '2026-08-03T10:00:00Z',
      );

      final forward = await _singleActivityItem(query);
      expect(forward.forwardOutcome, 'notInterested');
    });

    test('active help offer produces helping forward outcome', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 0,
        latestForwardAt: '2026-08-04T09:00:00Z',
      );
      await _insertHelpOffer(writer, beaconId: _foreignBeaconId, status: 0);

      final forward = await _singleActivityItem(query);
      expect(forward.forwardOutcome, 'helping');
      expect(forward.itemKind, AttentionItemKind.forward);
    });

    test('closedBeforeResponse and deletedBeforeResponse outcomes', () async {
      await _ensureForwardPath(writer, beaconId: _closedBeaconId);
      await _upsertInbox(
        writer,
        beaconId: _closedBeaconId,
        status: 1,
        latestForwardAt: '2026-08-05T11:00:00Z',
      );
      await writer.execute(
        Sql.named(
          'SELECT public.inbox_item_apply_tombstone_after_withdraw(@userId, @beaconId)',
        ),
        parameters: {'userId': _viewerId, 'beaconId': _closedBeaconId},
      );
      final closed = await _singleActivityItem(query);
      expect(closed.forwardOutcome, 'closedBeforeResponse');

      await _ensureForwardPath(writer, beaconId: _deletedBeaconId);
      await _upsertInbox(
        writer,
        beaconId: _deletedBeaconId,
        status: 1,
        latestForwardAt: '2026-08-06T11:00:00Z',
      );
      await writer.execute(
        Sql.named(
          'SELECT public.inbox_item_apply_tombstone_after_withdraw(@userId, @beaconId)',
        ),
        parameters: {'userId': _viewerId, 'beaconId': _deletedBeaconId},
      );
      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final deleted = feed.page.items
          .where((item) => item.id == 'inbox:$_deletedBeaconId')
          .single;
      expect(deleted.forwardOutcome, 'deletedBeforeResponse');
    });

    test('tombstone_dismissed_at hides the forward row', () async {
      await _ensureForwardPath(writer, beaconId: _closedBeaconId);
      await _upsertInbox(
        writer,
        beaconId: _closedBeaconId,
        status: 1,
        latestForwardAt: '2026-08-07T08:00:00Z',
      );
      await writer.execute(
        Sql.named(
          'SELECT public.inbox_item_apply_tombstone_after_withdraw(@userId, @beaconId)',
        ),
        parameters: {'userId': _viewerId, 'beaconId': _closedBeaconId},
      );
      await writer.execute(
        Sql.named('''
UPDATE public.inbox_item
SET tombstone_dismissed_at = now()
WHERE user_id = @userId AND beacon_id = @beaconId
'''),
        parameters: {'userId': _viewerId, 'beaconId': _closedBeaconId},
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(feed.page.items, isEmpty);
    });

    test('relay receipts dedupe into the forward item', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 1,
        latestForwardAt: '2026-08-08T12:00:00Z',
      );
      await _insertRelayReceipt(
        writer,
        id: 'Nactdedup01',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-01T12:00:00Z',
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(feed.page.items, hasLength(1));
      expect(feed.page.items.single.itemKind, AttentionItemKind.forward);
      expect(
        feed.page.items.any((item) => item.id == 'Nactdedup01'),
        isFalse,
      );
    });

    test('watching digest counts beacons not receipts', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 1,
        latestForwardAt: '2026-07-01T08:00:00Z',
      );
      await _insertRelayReceipt(
        writer,
        id: 'Nactdig01',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-10T10:00:00Z',
      );
      await _insertRelayReceipt(
        writer,
        id: 'Nactdig02',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-10T11:00:00Z',
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final digest = feed.page.items
          .where((item) => item.itemKind == AttentionItemKind.watchingDigest)
          .single;
      expect(digest.id, 'watching-digest');
      expect(digest.digestCount, 1);
      expect(
        feed.page.items.where((item) => item.itemKind == AttentionItemKind.forward),
        isEmpty,
      );
    });

    test(
      'cursor paging across receipts and forwards has no duplicates or gaps',
      () async {
        for (var index = 0; index < 60; index++) {
          await _insertProfileReceipt(
            writer,
            id: 'NactpgR$index',
            createdAt:
                '2026-06-01T12:${index.toString().padLeft(2, '0')}:00Z',
          );
        }
        for (var index = 0; index < 20; index++) {
          final beaconId = 'Bactpgfwd$index';
          await writer.execute(
            Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @authorId, @title, '', 0)
'''),
            parameters: {
              'id': beaconId,
              'authorId': _authorId,
              'title': 'Fwd $index',
            },
          );
          await _ensureForwardPath(writer, beaconId: beaconId);
          await _upsertInbox(
            writer,
            beaconId: beaconId,
            status: 1,
            latestForwardAt:
                '2026-09-01T14:${index.toString().padLeft(2, '0')}:00Z',
          );
        }

        const pageSize = 27;
        final collected = <AttentionReceipt>[];
        AttentionCursor? cursor;
        for (var page = 0; page < 3; page++) {
          final feed = await query.attentionFeed(
            accountId: _viewerId,
            view: AttentionFeedView.all,
            surface: AttentionSurface.activity,
            cursor: cursor,
            limit: pageSize,
          );
          final expectedOnPage = page < 2 ? pageSize : 80 - pageSize * 2;
          expect(feed.page.items, hasLength(expectedOnPage));
          collected.addAll(feed.page.items);
          cursor = feed.page.nextCursor;
          if (page < 2) {
            expect(cursor, isNotNull);
          } else {
            expect(cursor, isNull);
          }
        }

        expect(collected.map((item) => item.id).toSet(), hasLength(80));
        expect(collected, hasLength(80));
        for (var index = 1; index < collected.length; index++) {
          final previous = collected[index - 1];
          final current = collected[index];
          final isOrdered =
              previous.createdAt.isAfter(current.createdAt) ||
              (previous.createdAt == current.createdAt &&
                  previous.id.compareTo(current.id) > 0);
          expect(isOrdered, isTrue, reason: 'index $index');
        }
      },
    );

    test('demoted row above cursor appears on head refetch', () async {
      for (var index = 0; index < 5; index++) {
        await _insertProfileReceipt(
          writer,
          id: 'Nactdem$index',
          createdAt: '2026-05-0${index + 1}T12:00:00Z',
        );
      }
      final firstPage = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        limit: 2,
      );
      final cursor = firstPage.page.nextCursor!;

      await _insertProfileReceipt(
        writer,
        id: 'Nactdemoted',
        createdAt: '2026-06-15T12:00:00Z',
      );

      final head = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        limit: 5,
      );
      expect(head.page.items.first.id, 'Nactdemoted');

      final laterPage = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        cursor: cursor,
        limit: 10,
      );
      expect(
        laterPage.page.items.any((item) => item.id == 'Nactdemoted'),
        isFalse,
      );
      expect(laterPage.page.items, isNotEmpty);
    });

    test('unread_total includes receipts represented by forwards', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 1,
        latestForwardAt: '2026-08-09T09:00:00Z',
      );
      await _insertRelayReceipt(
        writer,
        id: 'Nactunread01',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-10T12:00:00Z',
      );
      await _insertProfileReceipt(writer, id: 'Nactunread02');

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.activity,
      );
      expect(feed.summary.unreadTotal, 2);
      expect(feed.page.items, hasLength(2));
    });
  }, skip: skipReason);
}

Future<AttentionReceipt> _singleActivityItem(AttentionRepository query) async {
  final feed = await query.attentionFeed(
    accountId: _viewerId,
    view: AttentionFeedView.all,
    surface: AttentionSurface.activity,
  );
  expect(feed.page.items, hasLength(1));
  return feed.page.items.single;
}

const _viewerId = 'Uactstream01';
const _authorId = 'Uactstream02';
const _ownedBeaconId = 'Bactstreamown';
const _foreignBeaconId = 'Bactstreamfor';
const _closedBeaconId = 'Bactstreamcls';
const _deletedBeaconId = 'Bactstreamdel';

Future<void> _ensureForwardPath(
  Connection writer, {
  required String beaconId,
}) async {
  await writer.execute(
    Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  @edgeId, @beaconId, @authorId, @viewerId, now(), NULL
)
ON CONFLICT DO NOTHING
'''),
    parameters: {
      'edgeId': 'FE$beaconId',
      'beaconId': beaconId,
      'authorId': _authorId,
      'viewerId': _viewerId,
    },
  );
}

Future<void> _upsertInbox(
  Connection writer, {
  required String beaconId,
  required int status,
  required String latestForwardAt,
  int forwardCount = 1,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.inbox_item (
  user_id, beacon_id, status, forward_count, latest_forward_at,
  latest_note_preview, rejection_message
) VALUES (
  @userId, @beaconId, @status, @forwardCount,
  CAST(@latestForwardAt AS timestamptz), '', ''
)
ON CONFLICT (user_id, beacon_id) DO UPDATE SET
  status = EXCLUDED.status,
  forward_count = EXCLUDED.forward_count,
  latest_forward_at = EXCLUDED.latest_forward_at
'''),
  parameters: {
    'userId': _viewerId,
    'beaconId': beaconId,
    'status': status,
    'forwardCount': forwardCount,
    'latestForwardAt': latestForwardAt,
  },
);

Future<void> _insertHelpOffer(
  Connection writer, {
  required String beaconId,
  required int status,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.beacon_help_offer (
  beacon_id, user_id, message, status, created_at, updated_at
) VALUES (@beaconId, @userId, 'offer', @status, now(), now())
'''),
  parameters: {
    'beaconId': beaconId,
    'userId': _viewerId,
    'status': status,
  },
);

Future<void> _insertRelayReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  String createdAt = '2026-07-16T12:00:00Z',
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'coordination', 'newRelay', 'normal',
  'Forwarded', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'relay_received', '{"eventType":"relayReceived"}'::jsonb,
  'standard', 'beacon_content'
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
  },
);

Future<void> _insertProfileReceipt(
  Connection writer, {
  required String id,
  String createdAt = '2026-07-16T12:00:00Z',
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at,
  source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'connections', 'inviteAccepted', 'normal',
  'Invite', 'Body', '/profile', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @sourceEventKey,
  'profile', 'invite_accepted', '{"eventType":"inviteAccepted"}'::jsonb,
  'standard', 'profile'
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'sourceEventKey': 'source-$id',
  },
);
