@Tags(['pg', 'mr'])
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
      // U10d: the grouped rows now carry §0.1a provenance, whose MR ranking
      // is `mr_mutual_scores` from pgmer2 — the same function the Inbox
      // computed field has always called.
      session = await setUpDisposablePgWriter(
        target: target,
        createPgmer2Extension: true,
      );
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

    // REWRITTEN IN U10c: a forward row's position is its *entry*, not its
    // latest forward. This fixture reaches the inbox twice — the shared
    // forward edge created it at `now()`, and `_upsertInbox` then backdates
    // `latest_forward_at` under it, which cannot happen in the live path —
    // so the assertion is stated against the anchor the trigger recorded
    // rather than against a forward time that precedes the Request's own
    // arrival.
    test('watching produces one forward item at its entry', () async {
      const at = '2026-08-02T14:30:00Z';
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 1,
        latestForwardAt: at,
      );
      final entryAt = await _firstEntryAt(writer, beaconId: _foreignBeaconId);

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final forward = feed.page.items.single;
      expect(forward.itemKind, AttentionItemKind.forward);
      expect(forward.id, 'inbox:$_foreignBeaconId');
      expect(forward.forwardOutcome, 'watching');
      expect(forward.createdAt.toUtc(), entryAt);
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

    // CHANGES IN U09/U10: cross-surface helping forward outcome duplicates My Work responsibility until projections apply D01/D08.
    test('active help offer produces helping forward outcome', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 0,
        latestForwardAt: '2026-08-04T09:00:00Z',
      );
      await _insertHelpOffer(writer, beaconId: _foreignBeaconId, status: 0);

      final forward = await _singleActivityItem(query);
      // CHANGES IN U09/U10: helping outcome row may become dismiss-only tombstone or leave Activity when live attention is My Work-only.
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
      // The individual forward row and the digest aggregate are independent
      // representations (design plan §5.6): a watched beacon keeps its own
      // "Вы наблюдаете" forward row at latest_forward_at regardless of
      // whether it also contributes to the digest count.
      final forwardRow = feed.page.items
          .where((item) => item.itemKind == AttentionItemKind.forward)
          .single;
      expect(forwardRow.id, 'inbox:$_foreignBeaconId');
      expect(forwardRow.forwardOutcome, 'watching');
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
      // REWRITTEN IN U15R-a (was: three rows, the outcome row among them).
      // An outcome row carries no dot (owner decision B), so it is not a
      // member of the *unread* view any more — the digest and the unrelated
      // profile receipt are. The row itself is untouched in the `all` view
      // below: still present, still dismissible, still where it entered.
      expect(feed.page.items, hasLength(2));
      expect(
        feed.page.items.map((item) => item.itemKind),
        containsAll(<AttentionItemKind>[
          AttentionItemKind.watchingDigest,
          AttentionItemKind.receipt,
        ]),
      );
      final all = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(
        all.page.items.where(
          (item) => item.itemKind == AttentionItemKind.forward,
        ),
        hasLength(1),
      );
    });

    test('two status events without inbox coalesce to requestActivity', () async {
      await _ensureForwardPath(writer, beaconId: _foreignBeaconId);
      await _insertStatusReceipt(
        writer,
        id: 'NactstA001',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-10T10:00:00Z',
      );
      await _insertStatusReceipt(
        writer,
        id: 'NactstA002',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-10T12:00:00Z',
      );
      // Forward edges auto-create an open inbox row; remove it so events have
      // no eligible representative and must coalesce onto requestActivity.
      await writer.execute(
        Sql.named(
          'DELETE FROM public.inbox_item WHERE user_id = @u AND beacon_id = @b',
        ),
        parameters: {'u': _viewerId, 'b': _foreignBeaconId},
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final grouped = feed.page.items
          .where((item) => item.itemKind == AttentionItemKind.requestActivity)
          .toList();
      expect(grouped, hasLength(1));
      expect(grouped.single.id, 'activity-beacon:$_foreignBeaconId');
      // REWRITTEN IN U10c: a synthetic group sits at the child that put it on
      // the surface (10:00), not at its newest one (12:00). It has no inbox
      // row and therefore no `first_entry_at`; its first child is the entry.
      expect(
        grouped.single.createdAt.toUtc().toIso8601String(),
        '2026-08-10T10:00:00.000Z',
      );
      expect(grouped.single.eventTotal, 2);
      expect(grouped.single.eventsPreview, hasLength(2));
      expect(
        feed.page.items
            .where((item) => item.itemKind == AttentionItemKind.receipt),
        isEmpty,
      );
    });

    test('distinct beacons stay distinct requestActivity rows', () async {
      await _ensureForwardPath(writer, beaconId: _foreignBeaconId);
      await writer.execute(
        Sql.named('''
INSERT INTO public.beacon (id, user_id, title, description, status)
VALUES (@id, @authorId, 'Foreign2', 'Foreign request 2', 0)
ON CONFLICT DO NOTHING
'''),
        parameters: {'id': _foreignBeacon2Id, 'authorId': _authorId},
      );
      await _ensureForwardPath(writer, beaconId: _foreignBeacon2Id);
      await _insertStatusReceipt(
        writer,
        id: 'NactstB001',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-11T10:00:00Z',
      );
      await _insertStatusReceipt(
        writer,
        id: 'NactstB002',
        beaconId: _foreignBeacon2Id,
        createdAt: '2026-08-11T11:00:00Z',
      );
      await writer.execute(
        Sql.named(
          'DELETE FROM public.inbox_item WHERE user_id = @u',
        ),
        parameters: {'u': _viewerId},
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final grouped = feed.page.items
          .where((item) => item.itemKind == AttentionItemKind.requestActivity)
          .toList();
      expect(grouped.map((e) => e.beaconId).toSet(), {
        _foreignBeaconId,
        _foreignBeacon2Id,
      });
    });

    // REWRITTEN IN U10c (was: `status event merges into forward and bumps
    // created_at`). The merge is unchanged; the bump is gone. Section 6: an
    // optional update changes a dot, a preview and an event list — never a
    // position.
    test('status event merges into forward without moving it', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 1,
        latestForwardAt: '2026-08-12T08:00:00Z',
      );
      await _insertRelayReceipt(
        writer,
        id: 'NactstC001',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-12T08:00:00Z',
      );
      await _insertStatusReceipt(
        writer,
        id: 'NactstC002',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-12T14:00:00Z',
      );
      await writer.execute(
        Sql.named(
          "UPDATE public.notification_outbox SET seen_at = now() WHERE id = 'NactstC001'",
        ),
      );

      final entryAt = await _firstEntryAt(writer, beaconId: _foreignBeaconId);

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final forward = feed.page.items
          .where((item) => item.id == 'inbox:$_foreignBeaconId')
          .single;
      expect(forward.itemKind, AttentionItemKind.forward);
      // The status event is two days newer than anything else here. Before
      // U10c it became the row's `created_at`; now the row stays at the
      // Request's entry and only the dot, the count and the preview move.
      expect(forward.createdAt.toUtc(), entryAt);
      // REWRITTEN IN U15R-a (was: the outcome row took the dot and the count
      // from the event). Decision B gives an outcome row neither; the event
      // is carried by the Request's own row, which is where the person acts
      // on it. Nothing is lost — it moved to the object it belongs to.
      expect(forward.isUnread, isFalse);
      expect(forward.eventTotal, 0);
      final group = feed.page.items
          .where((item) => item.itemKind == AttentionItemKind.requestActivity)
          .single;
      expect(group.beaconId, _foreignBeaconId);
      expect(group.eventTotal, 1);
      expect(group.eventUnseenCount, 1);
      expect(
        feed.page.items.where(
          (item) =>
              item.itemKind == AttentionItemKind.receipt &&
              item.beaconId == _foreignBeaconId,
        ),
        isEmpty,
      );
    });

    // CHANGES IN U09/U10: helping forward row presentation and Activity grouping may change with outcome dismiss and active-only eligibility.
    test('helping forward has zero Activity event children', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 0,
        latestForwardAt: '2026-08-13T08:00:00Z',
      );
      await _insertHelpOffer(writer, beaconId: _foreignBeaconId, status: 0);
      await _insertStatusReceipt(
        writer,
        id: 'NactstD001',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-13T09:00:00Z',
      );

      final forward = await _singleActivityItem(query);
      // CHANGES IN U09/U10: event children eligibility may include uncleared optional updates under active-only grouping.
      expect(forward.forwardOutcome, 'helping');
      expect(forward.eventTotal, 0);
      expect(forward.eventsPreview, isEmpty);
    });

    // REWRITTEN IN U15R-a. The property this protects is unchanged — a
    // dismissed tombstone never comes back — but it used to be asserted by
    // the whole surface going empty, which is how R1 hid: the Request's live
    // optional event was vetoed along with the memory, while the tab kept
    // counting it. The tombstone row stays gone; the event is reachable.
    test('dismissed tombstone stays dismissed and does not veto its Request',
        () async {
      await _ensureForwardPath(writer, beaconId: _closedBeaconId);
      await _upsertInbox(
        writer,
        beaconId: _closedBeaconId,
        status: 1,
        latestForwardAt: '2026-08-14T08:00:00Z',
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
      await _insertStatusReceipt(
        writer,
        id: 'NactstE001',
        beaconId: _closedBeaconId,
        createdAt: '2026-08-14T09:00:00Z',
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(
        feed.page.items.any((item) => item.id == 'inbox:$_closedBeaconId'),
        isFalse,
        reason: 'the dismissed memory never returns',
      );
      final group = feed.page.items.single;
      expect(group.itemKind, AttentionItemKind.requestActivity);
      expect(group.beaconId, _closedBeaconId);
      expect(group.eventUnseenCount, 1);
    });

    // U15R-a / R1 — the seam Astra found: an outcome dismissal is a memory
    // being put away, never a veto on the Request's live attention. The tab
    // total counts the uncleared optional receipt either way (summary), so a
    // projection that drops the Request leaves the tab lit over a surface
    // with nothing on it — the M1 failure stated from both sides at once.
    //
    // Both quantities here come from the server: the number from
    // `surfaceSummary`, the list from `attentionFeed`. Neither is a
    // hand-built value that merely looks right.
    test(
      'an outcome-only dismissal leaves later optional attention reachable',
      () async {
        await _upsertInbox(
          writer,
          beaconId: _foreignBeaconId,
          status: 1,
          latestForwardAt: '2026-08-20T08:00:00Z',
        );
        await writer.execute(
          Sql.named('''
UPDATE public.inbox_item
SET tombstone_dismissed_at = now()
WHERE user_id = @userId AND beacon_id = @beaconId
'''),
          parameters: {'userId': _viewerId, 'beaconId': _foreignBeaconId},
        );
        // …and only then does the next optional event arrive.
        await _insertStatusReceipt(
          writer,
          id: 'NactR1a001',
          beaconId: _foreignBeaconId,
          createdAt: '2026-08-20T09:00:00Z',
        );

        final summary = await query.surfaceSummary(accountId: _viewerId);
        final feed = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.all,
          surface: AttentionSurface.activity,
        );

        expect(
          summary.forYouDot,
          isTrue,
          reason: 'the uncleared optional receipt still lights the tab. '
              'CHANGES IN U18c — this read the legacy `activityUnreadTotal`; '
              '§6 says `for you.count = never`, so the dot is the whole of '
              'what For You says.',
        );
        final forBeacon = feed.page.items
            .where((item) => item.beaconId == _foreignBeaconId)
            .toList();
        expect(
          forBeacon,
          isNotEmpty,
          reason: 'what the tab counts must be reachable on the surface',
        );
        final group = forBeacon.single;
        expect(group.itemKind, AttentionItemKind.requestActivity);
        expect(group.eventUnseenCount, 1);
        expect(
          feed.page.items.any((item) => item.id == 'inbox:$_foreignBeaconId'),
          isFalse,
          reason: 'the dismissed tombstone itself never comes back',
        );
      },
    );

    // U15R-a / R1, decision B's other half: an outcome row is a trace of the
    // viewer's own past act — "no dot and no sub-cards" (contract §7). Its
    // Request's live attention is not lost; it is reachable as its own row.
    test('a non-helping outcome row carries no dot and no sub-cards', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 1,
        latestForwardAt: '2026-08-21T08:00:00Z',
      );
      await _insertStatusReceipt(
        writer,
        id: 'NactR1b001',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-21T09:00:00Z',
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final outcome = feed.page.items
          .where((item) => item.id == 'inbox:$_foreignBeaconId')
          .single;
      expect(outcome.forwardOutcome, 'watching');
      expect(outcome.eventTotal, 0);
      expect(outcome.eventUnseenCount, 0);
      expect(outcome.eventsPreview, isEmpty);
      expect(
        outcome.isUnread,
        isFalse,
        reason: 'an outcome row is never a second attention object',
      );

      final group = feed.page.items
          .where((item) => item.itemKind == AttentionItemKind.requestActivity)
          .single;
      expect(group.beaconId, _foreignBeaconId);
      expect(group.eventUnseenCount, 1);
      expect(group.eventsPreview, hasLength(1));
    });

    test('beacon-less activity receipt stays a standalone receipt row', () async {
      await _insertProfileReceipt(writer, id: 'Nactgrp01');

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(feed.page.items, hasLength(1));
      expect(feed.page.items.single.itemKind, AttentionItemKind.receipt);
      expect(feed.page.items.single.beaconId, isNull);
    });

    test(
      'beacon status receipt coalesces under open pinned forward not standalone',
      () async {
        await _upsertInbox(
          writer,
          beaconId: _foreignBeaconId,
          status: 0,
          latestForwardAt: '2026-08-16T08:00:00Z',
        );
        await _insertStatusReceipt(
          writer,
          id: 'Nactgrp02',
          beaconId: _foreignBeaconId,
          createdAt: '2026-08-16T09:00:00Z',
        );

        final feed = await query.attentionFeed(
          accountId: _viewerId,
          view: AttentionFeedView.all,
          surface: AttentionSurface.activity,
        );
        expect(
          feed.page.items.where(
            (item) => item.itemKind == AttentionItemKind.receipt,
          ),
          isEmpty,
        );

        final offers = await query.activityOffers(
          accountId: _viewerId,
          limit: 10,
        );
        expect(offers.totalCount, 1);
        expect(offers.items.single.beaconId, _foreignBeaconId);
        expect(offers.items.single.eventTotal, 1);
      },
    );

    test('unanswered open forward appears only in activityOffers pinned set',
        () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 0,
        latestForwardAt: '2026-08-17T08:00:00Z',
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(
        feed.page.items.where(
          (item) => item.itemKind == AttentionItemKind.forward,
        ),
        isEmpty,
      );

      final offers = await query.activityOffers(
        accountId: _viewerId,
        limit: 10,
      );
      expect(offers.totalCount, 1);
      expect(offers.items.single.beaconId, _foreignBeaconId);
    });

    test('watching status removes beacon from activityOffers pinned set', () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 1,
        latestForwardAt: '2026-08-18T08:00:00Z',
      );

      final offers = await query.activityOffers(
        accountId: _viewerId,
        limit: 10,
      );
      expect(offers.totalCount, 0);

      final forward = await _singleActivityItem(query);
      expect(forward.itemKind, AttentionItemKind.forward);
      expect(forward.forwardOutcome, 'watching');
    });

    test('active help offer removes beacon from activityOffers pinned set',
        () async {
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 0,
        latestForwardAt: '2026-08-19T08:00:00Z',
      );
      await _insertHelpOffer(writer, beaconId: _foreignBeaconId, status: 0);

      final offers = await query.activityOffers(
        accountId: _viewerId,
        limit: 10,
      );
      expect(offers.totalCount, 0);
    });

    // REWRITTEN IN U10c (was: `activityOffers orders by effectiveActivityAt
    // not latest_forward_at`). Neither key orders the zone any more: the
    // position key does, and `effectiveActivityAt` survives only as the
    // latest-event key the card renders.
    test('activityOffers orders the pinned zone by entry, not by either',
        () async {
      await _ensureForwardPath(writer, beaconId: _foreignBeaconId);
      await _ensureForwardPath(writer, beaconId: _closedBeaconId);
      await _upsertInbox(
        writer,
        beaconId: _foreignBeaconId,
        status: 0,
        latestForwardAt: '2026-08-15T08:00:00Z',
      );
      await _insertStatusReceipt(
        writer,
        id: 'NactstF001',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-15T20:00:00Z',
      );
      await _upsertInbox(
        writer,
        beaconId: _closedBeaconId,
        status: 0,
        latestForwardAt: '2026-08-15T12:00:00Z',
      );

      final page = await query.activityOffers(accountId: _viewerId, limit: 10);
      // Both Requests entered when `_ensureForwardPath` created their inbox
      // rows, `_closedBeaconId` second, so it sits above — and the status
      // event on `_foreignBeaconId`, newer than everything in the fixture,
      // does not lift it. Under the old key it did.
      expect(page.items.map((e) => e.beaconId).toList(), [
        _closedBeaconId,
        _foreignBeaconId,
      ]);
      final foreign = page.items
          .where((row) => row.beaconId == _foreignBeaconId)
          .single;
      expect(
        foreign.eventTotal,
        1,
        reason: 'the event still attaches to its Request — it just does not '
            'move it',
      );
      expect(foreign.eventsPreview, hasLength(1));
      expect(
        foreign.effectiveActivityAt.toUtc().toIso8601String(),
        '2026-08-15T20:00:00.000Z',
        reason: 'the latest-event key did move; it is simply not the key the '
            'zone is ordered by',
      );
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
const _foreignBeacon2Id = 'Bactstreamfo2';
const _closedBeaconId = 'Bactstreamcls';
const _deletedBeaconId = 'Bactstreamdel';

/// The stable ordering anchor `attention_request_state` recorded when this
/// Request entered the viewer's attention (U09a's trigger, U10c's `LEAST`).
Future<DateTime> _firstEntryAt(
  Connection writer, {
  required String beaconId,
}) async {
  final rows = await writer.execute(
    Sql.named('''
SELECT first_entry_at
FROM public.attention_request_state
WHERE account_id = @u AND beacon_id = @b
'''),
    parameters: {'u': _viewerId, 'b': beaconId},
  );
  return (rows.single[0]! as DateTime).toUtc();
}

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

Future<void> _insertStatusReceipt(
  Connection writer, {
  required String id,
  required String beaconId,
  required String createdAt,
  bool seen = false,
}) => writer.execute(
  Sql.named('''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key, created_at, seen_at,
  beacon_id, source_event_key,
  destination_kind, presentation_key, presentation_payload,
  suppression_class, access_policy
) VALUES (
  @id, @accountId, 'coordination', 'coordinationChanged', 'normal',
  'Status changed', 'Body', '/attention', @dedupKey,
  CAST(@createdAt AS timestamptz),
  CASE WHEN @seen THEN CAST(@createdAt AS timestamptz) ELSE NULL END,
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
    'seen': seen,
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
