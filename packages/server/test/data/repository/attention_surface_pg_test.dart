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
    envVarName: 'TENTURA_ATTENTION_SURFACE_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_surface',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('attention surface reads and mark-all', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository query;
    late AttentionAckRepository ack;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      query = AttentionRepository(database);
      ack = AttentionAckRepository(database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.beacon_help_offer,
  public.beacon_archived,
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
  (@foreignId, @authorId, 'Foreign', 'Foreign request', 0)
'''),
        parameters: {
          'ownedId': _ownedBeaconId,
          'foreignId': _foreignBeaconId,
          'viewerId': _viewerId,
          'authorId': _authorId,
        },
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    test('authored open receipt is myWork', () async {
      await _insertBeaconReceipt(
        writer,
        id: 'Nsurf01',
        beaconId: _ownedBeaconId,
      );
      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.myWork,
      );
      expect(feed.page.items.single.surface, AttentionSurface.myWork);
      expect(feed.page.items.single.itemKind, AttentionItemKind.receipt);
    });

    test('authored archived beacon receipt stays myWork', () async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_archived (user_id, beacon_id, archived_at)
VALUES (@userId, @beaconId, now())
'''),
        parameters: {'userId': _viewerId, 'beaconId': _ownedBeaconId},
      );
      await _insertBeaconReceipt(
        writer,
        id: 'Nsurf02',
        beaconId: _ownedBeaconId,
      );
      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.myWork,
      );
      expect(item.surface, AttentionSurface.myWork);
    });

    test('active help offer puts foreign beacon receipt on myWork', () async {
      await _insertHelpOffer(writer, beaconId: _foreignBeaconId, status: 0);
      await _insertBeaconReceipt(
        writer,
        id: 'Nsurf03',
        beaconId: _foreignBeaconId,
      );
      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.myWork,
      );
      expect(item.surface, AttentionSurface.myWork);
    });

    test('obligation on foreign beacon is myWork via scope union', () async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  'FEattnsurf02', @beaconId, @authorId, @viewerId, now(), NULL
)
'''),
        parameters: {
          'beaconId': _foreignBeaconId,
          'authorId': _authorId,
          'viewerId': _viewerId,
        },
      );
      await _insertLiveObligationReceipt(
        writer,
        id: 'Nsurf04',
        beaconId: _foreignBeaconId,
      );
      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.myWork,
      );
      expect(item.surface, AttentionSurface.myWork);
      expect(item.requiresAction, isTrue);
    });

    test('forward-only recipient receipt is activity', () async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  'FEattnsurf01', @beaconId, @authorId, @viewerId, now(), NULL
)
'''),
        parameters: {
          'beaconId': _foreignBeaconId,
          'authorId': _authorId,
          'viewerId': _viewerId,
        },
      );
      await _insertBeaconReceipt(
        writer,
        id: 'Nsurf05',
        beaconId: _foreignBeaconId,
      );
      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.activity,
      );
      expect(item.surface, AttentionSurface.activity);
    });

    test('beacon-less invite_accepted is activity', () async {
      await _insertProfileReceipt(writer, id: 'Nsurf06');
      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.activity,
      );
      expect(item.surface, AttentionSurface.activity);
      expect(item.beaconId, isNull);
    });

    test('withdrawn help offer leaves foreign beacon on activity', () async {
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (
  'FEattnsurf03', @beaconId, @authorId, @viewerId, now(), NULL
)
'''),
        parameters: {
          'beaconId': _foreignBeaconId,
          'authorId': _authorId,
          'viewerId': _viewerId,
        },
      );
      await _insertHelpOffer(writer, beaconId: _foreignBeaconId, status: 1);
      await _insertBeaconReceipt(
        writer,
        id: 'Nsurf07',
        beaconId: _foreignBeaconId,
      );
      final item = await _singleReceipt(
        query,
        surface: AttentionSurface.activity,
      );
      expect(item.surface, AttentionSurface.activity);
    });

    test('per-surface unread totals and needsYouTotal stays global', () async {
      await _insertBeaconReceipt(
        writer,
        id: 'Nsurf08mw',
        beaconId: _ownedBeaconId,
      );
      await _insertProfileReceipt(writer, id: 'Nsurf08act');
      await _insertLiveObligationReceipt(
        writer,
        id: 'Nsurf08obl',
        beaconId: _ownedBeaconId,
      );

      final myWorkFeed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.myWork,
      );
      final activityFeed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.activity,
      );
      final allFeed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
      );
      final surfaceSummary = await query.surfaceSummary(accountId: _viewerId);

      expect(myWorkFeed.summary.unreadTotal, 2);
      expect(activityFeed.summary.unreadTotal, 1);
      expect(allFeed.summary.unreadTotal, 3);
      expect(myWorkFeed.summary.needsYouTotal, 1);
      expect(activityFeed.summary.needsYouTotal, 1);
      expect(surfaceSummary.activityUnreadTotal, 1);
      expect(surfaceSummary.myWorkUnreadTotal, 2);
      expect(surfaceSummary.needsYouTotal, 1);
    });

    test('markAllSeen(activity) leaves myWork receipts unseen', () async {
      await _insertBeaconReceipt(
        writer,
        id: 'Nsurf09mw',
        beaconId: _ownedBeaconId,
      );
      await _insertProfileReceipt(writer, id: 'Nsurf09act');

      expect(
        await ack.markAllSeen(_viewerId, surface: AttentionSurface.activity),
        1,
      );
      await _assertUnread(writer, 'Nsurf09mw');
      await _assertSeen(writer, 'Nsurf09act');
    });

    test('surface null matches legacy all-surface feed snapshot', () async {
      await _insertBeaconReceipt(
        writer,
        id: 'Nsurf10a',
        beaconId: _ownedBeaconId,
        createdAt: '2026-07-16T14:00:00Z',
      );
      await _insertProfileReceipt(
        writer,
        id: 'Nsurf10b',
        createdAt: '2026-07-16T13:00:00Z',
      );
      await _insertLiveObligationReceipt(
        writer,
        id: 'Nsurf10c',
        beaconId: _ownedBeaconId,
        createdAt: '2026-07-16T12:00:00Z',
      );

      final implicit = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
      );
      final explicitNull = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: null,
      );

      expect(explicitNull.summary.unreadTotal, implicit.summary.unreadTotal);
      expect(explicitNull.summary.needsYouTotal, implicit.summary.needsYouTotal);
      expect(
        explicitNull.page.items.map((item) => item.id).toList(),
        implicit.page.items.map((item) => item.id).toList(),
      );
      for (final item in implicit.page.items) {
        expect(item.itemKind, AttentionItemKind.receipt);
      }
    });

    test('cursor paging under activity filter has no duplicates or gaps', () async {
      for (var index = 0; index < 6; index++) {
        await _insertProfileReceipt(
          writer,
          id: 'Nsurf11$index',
          createdAt:
              '2026-07-10T${(10 + index).toString().padLeft(2, '0')}:00:00Z',
        );
      }

      final collected = <String>[];
      AttentionCursor? cursor;
      for (var page = 0; page < 3; page++) {
        final feed = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.all,
          surface: AttentionSurface.activity,
          cursor: cursor,
          limit: 2,
        );
        expect(feed.page.items, hasLength(2));
        collected.addAll(feed.page.items.map((item) => item.id));
        cursor = feed.page.nextCursor;
        if (page < 2) {
          expect(cursor, isNotNull, reason: 'page $page should have next cursor');
        } else {
          expect(cursor, isNull, reason: 'final page should not have next cursor');
        }
      }
      expect(collected.toSet(), hasLength(6));
      expect(collected, hasLength(6));
    });
  }, skip: skipReason);
}

Future<AttentionReceipt> _singleReceipt(
  AttentionRepository query, {
  required AttentionSurface surface,
}) async {
  final feed = await query.attentionFeed(
    accountId: _viewerId,
    view: AttentionFeedView.all,
    surface: surface,
  );
  expect(feed.page.items, hasLength(1));
  return feed.page.items.single;
}

const _viewerId = 'Uattnsurf01';
const _authorId = 'Uattnsurf02';
const _ownedBeaconId = 'Battnsurfown';
const _foreignBeaconId = 'Battnsurffore';

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

Future<void> _insertBeaconReceipt(
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
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Title', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
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

Future<void> _insertLiveObligationReceipt(
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
  suppression_class, access_policy,
  requires_action, attention_thread_key
) VALUES (
  @id, @accountId, 'asksOfMe', 'needsMe', 'normal',
  'Obligation', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  @beaconId, @sourceEventKey,
  'beacon', 'request_status_changed', '{"eventType":"fixture"}'::jsonb,
  'standard', 'beacon_content',
  true, @threadKey
)
'''),
  parameters: {
    'id': id,
    'accountId': _viewerId,
    'dedupKey': 'dedup-$id',
    'createdAt': createdAt,
    'beaconId': beaconId,
    'sourceEventKey': 'source-$id',
    'threadKey': 'v1|needsMe|$id|$_viewerId',
  },
);

Future<void> _assertSeen(Connection writer, String id) async {
  final row = await writer.execute(
    Sql.named('SELECT seen_at FROM public.notification_outbox WHERE id = @id'),
    parameters: {'id': id},
  );
  expect(row.single[0], isNotNull);
}

Future<void> _assertUnread(Connection writer, String id) async {
  final row = await writer.execute(
    Sql.named('SELECT seen_at FROM public.notification_outbox WHERE id = @id'),
    parameters: {'id': id},
  );
  expect(row.single[0], isNull);
}
