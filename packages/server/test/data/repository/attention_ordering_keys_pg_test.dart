@Tags(['pg'])
library;

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

/// U10c — the bumping key and the latest-event key are two different keys.
///
/// §6: *an optional update changes a dot, a preview and an event list — never
/// a position*; *a Request entering a surface establishes its place then; it
/// keeps it*. D08 adds the one exception: **a new obligation promotes**.
///
/// Until this unit every grouped row was ordered by
/// `GREATEST(latest_forward_at, max child created_at)` — one key doing both
/// jobs, so every non-bumping receipt (a child event, a tombstone, a
/// timeline-only row) moved the Request it belonged to. U10b pinned that as a
/// named defect rather than inherit it silently; this suite is where the
/// expectation flips.
///
/// The keys after this unit:
///
/// | Row shape | position key (`created_at` / `listPositionAt`) | latest-event key |
/// |---|---|---|
/// | pinned / forward (`inbox_item`-backed) | `attention_request_state.first_entry_at`, falling back to `latest_forward_at` | `effectiveActivityAt` |
/// | `requestActivity` (no inbox row) | `MIN(child.created_at)` — its first entry | `MAX(child.created_at)` |
/// | standalone receipt | its own immutable `created_at` | same |
/// | My Desk `Needs you` | latest live-obligation `created_at`, then first entry, then id | — |
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_ORDERING_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_order',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('U10c — ordering keys', () {
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
  public.attention_request_state,
  public.beacon_help_offer,
  public.beacon_archived,
  public.beacon_forward_edge,
  public.notification_outbox,
  public.beacon,
  public."user"
CASCADE
''');
      for (final id in [_viewerId, _authorId, _secondSenderId]) {
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
  (@owned2Id, @viewerId, 'Owned 2', 'Owned request 2', 0),
  (@earlyId, @authorId, 'Early', 'Early request', 0),
  (@lateId, @authorId, 'Late', 'Late request', 0)
'''),
        parameters: {
          'ownedId': _ownedBeaconId,
          'owned2Id': _owned2BeaconId,
          'earlyId': _earlyBeaconId,
          'lateId': _lateBeaconId,
          'viewerId': _viewerId,
          'authorId': _authorId,
        },
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    // ------------------------------------------- the pinned zone is stable

    test('an optional event arriving does not move a pinned Request', () async {
      await _forwardEdge(
        writer,
        id: 'FEord01',
        beaconId: _lateBeaconId,
        createdAt: '2026-08-10T10:00:00Z',
      );
      await _forwardEdge(
        writer,
        id: 'FEord02',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );

      final before = await query.activityOffers(accountId: _viewerId);
      expect(before.items.map((row) => row.beaconId).toList(), [
        _lateBeaconId,
        _earlyBeaconId,
      ]);

      // The optional event lands on the *lower* card and is newer than the
      // other card's whole history. Under the old single key this alone
      // flipped the zone.
      await _optional(
        writer,
        id: 'Nord01',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-12T14:00:00Z',
      );

      final after = await query.activityOffers(accountId: _viewerId);
      expect(
        after.items.map((row) => row.beaconId).toList(),
        [_lateBeaconId, _earlyBeaconId],
        reason:
            '§6: an optional update changes a dot, a preview and an event '
            'list — never a position',
      );
      expect(
        after.items.last.eventUnseenCount,
        1,
        reason: 'the dot and the preview do move — that is the whole point',
      );
      expect(after.items.last.eventsPreview, hasLength(1));
    });

    test('the latest-event key still moves while the position key does not',
        () async {
      await _forwardEdge(
        writer,
        id: 'FEord03',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      final before =
          (await query.activityOffers(accountId: _viewerId)).items.single;

      await _optional(
        writer,
        id: 'Nord02',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-12T14:00:00Z',
      );
      final after =
          (await query.activityOffers(accountId: _viewerId)).items.single;

      expect(
        after.listPositionAt,
        before.listPositionAt,
        reason: 'the bumping key is the Request\'s entry, and it did not enter '
            'again',
      );
      expect(
        after.effectiveActivityAt.isAfter(before.effectiveActivityAt),
        isTrue,
        reason: 'the latest-event key is a separate key and still tracks the '
            'newest event, which is what a preview is rendered from',
      );
    });

    test('a repeated forward does not move an existing pinned Request',
        () async {
      await _forwardEdge(
        writer,
        id: 'FEord04',
        beaconId: _lateBeaconId,
        createdAt: '2026-08-10T10:00:00Z',
      );
      await _forwardEdge(
        writer,
        id: 'FEord05',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      // A second sender forwards the lower card, long after both entered.
      await _forwardEdge(
        writer,
        id: 'FEord06',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-20T09:00:00Z',
        senderId: _secondSenderId,
      );

      final page = await query.activityOffers(accountId: _viewerId);
      expect(
        page.items.map((row) => row.beaconId).toList(),
        [_lateBeaconId, _earlyBeaconId],
        reason:
            'D08: a repeated forward does not reorder an existing pinned card',
      );
    });

    // --------------------------------------------- the grouped feed shapes

    test('a forward row sits at its entry, not at its newest child event',
        () async {
      await _forwardEdge(
        writer,
        id: 'FEord07',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      await _watching(writer, beaconId: _earlyBeaconId);
      await _optional(
        writer,
        id: 'Nord03',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-12T14:00:00Z',
      );
      // A standalone profile receipt in between the two, as a ruler.
      await _profile(writer, id: 'Nord04', createdAt: '2026-08-11T12:00:00Z');

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final forward = feed.page.items
          .where((item) => item.id == 'inbox:$_earlyBeaconId')
          .single;
      expect(
        forward.createdAt.toUtc().toIso8601String(),
        '2026-08-10T09:00:00.000Z',
      );
      final ids = feed.page.items.map((item) => item.id).toList();
      expect(
        ids.indexOf('Nord04'),
        lessThan(ids.indexOf('inbox:$_earlyBeaconId')),
        reason: 'the optional child did not lift the forward over the ruler',
      );
    });

    test('a requestActivity group sits at its first child, not its latest',
        () async {
      await _forwardEdge(
        writer,
        id: 'FEordRA1',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-09T09:00:00Z',
      );
      await _detachInbox(writer, beaconId: _earlyBeaconId);
      await _optional(
        writer,
        id: 'Nord05',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      await _profile(writer, id: 'Nord06', createdAt: '2026-08-11T12:00:00Z');

      final firstFeed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(firstFeed.page.items.map((item) => item.id).toList(), [
        'Nord06',
        'activity-beacon:$_earlyBeaconId',
      ]);

      await _optional(
        writer,
        id: 'Nord07',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-12T14:00:00Z',
      );

      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(
        feed.page.items.map((item) => item.id).toList(),
        ['Nord06', 'activity-beacon:$_earlyBeaconId'],
        reason:
            'a group with no inbox row has no first_entry_at; its entry is the '
            'first child that put it on the surface, and that child does not '
            'move when a second one arrives',
      );
      expect(
        feed.page.items.last.eventTotal,
        2,
        reason: 'the list behind the group did grow',
      );
    });

    test('clearing a child moves neither the group nor the zone', () async {
      await _forwardEdge(
        writer,
        id: 'FEordRA2',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-09T09:00:00Z',
      );
      await _detachInbox(writer, beaconId: _earlyBeaconId);
      await _optional(
        writer,
        id: 'Nord08',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      await _optional(
        writer,
        id: 'Nord09',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-12T14:00:00Z',
      );
      final before = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      final beforeAt = before.page.items.single.createdAt;

      await _clearReceipt(writer, 'Nord08');

      final after = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(
        after.page.items.single.createdAt,
        beforeAt,
        reason: 'clearing is not entering: the earliest child is still what '
            'put the group on the surface',
      );
    });

    // ------------------------------------------------ My Desk `Needs you`

    test('Needs you orders by latest live-obligation creation', () async {
      await _obligation(
        writer,
        id: 'Nord10',
        beaconId: _ownedBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      await _obligation(
        writer,
        id: 'Nord11',
        beaconId: _owned2BeaconId,
        createdAt: '2026-08-11T09:00:00Z',
      );

      final before = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId, _owned2BeaconId},
      );
      expect(before.map((row) => row.beaconId).toList(), [
        _owned2BeaconId,
        _ownedBeaconId,
      ]);

      // A new obligation on the lower Request promotes it — the one thing
      // that may move a Request (D08).
      await _obligation(
        writer,
        id: 'Nord12',
        beaconId: _ownedBeaconId,
        createdAt: '2026-08-12T09:00:00Z',
      );

      final after = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId, _owned2BeaconId},
      );
      expect(after.map((row) => row.beaconId).toList(), [
        _ownedBeaconId,
        _owned2BeaconId,
      ]);
      expect(
        after.first.needsYouAt?.toUtc().toIso8601String(),
        '2026-08-12T09:00:00.000Z',
      );
    });

    test('an optional event does not reorder Needs you', () async {
      await _obligation(
        writer,
        id: 'Nord13',
        beaconId: _ownedBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      await _obligation(
        writer,
        id: 'Nord14',
        beaconId: _owned2BeaconId,
        createdAt: '2026-08-11T09:00:00Z',
      );
      await _optional(
        writer,
        id: 'Nord15',
        beaconId: _ownedBeaconId,
        createdAt: '2026-08-20T09:00:00Z',
      );

      final rows = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId, _owned2BeaconId},
      );
      expect(
        rows.map((row) => row.beaconId).toList(),
        [_owned2BeaconId, _ownedBeaconId],
        reason:
            'the newest thing on the owned Request is optional; §6 says that '
            'never changes a position',
      );
    });

    test('a Request with no obligation sorts below every Request with one',
        () async {
      await _optional(
        writer,
        id: 'Nord16',
        beaconId: _ownedBeaconId,
        createdAt: '2026-08-20T09:00:00Z',
      );
      await _obligation(
        writer,
        id: 'Nord17',
        beaconId: _owned2BeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );

      final rows = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId, _owned2BeaconId},
      );
      expect(rows.map((row) => row.beaconId).toList(), [
        _owned2BeaconId,
        _ownedBeaconId,
      ]);
      expect(rows.last.needsYouAt, isNull);
      expect(
        rows.last.firstEntryAt,
        isNotNull,
        reason: 'the fallback ordering anchor is populated for every row it '
            'orders — an obligation-less My Desk Request has no inbox row, so '
            'its anchor is its earliest active receipt',
      );
    });

    // ---------------------------------------------------- `first_entry_at`

    test('every inbox-backed Request has an entry anchor at its first forward',
        () async {
      await _forwardEdge(
        writer,
        id: 'FEord08',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      await _forwardEdge(
        writer,
        id: 'FEord09',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-20T09:00:00Z',
        senderId: _secondSenderId,
      );

      final rows = await writer.execute(
        Sql.named('''
SELECT first_entry_at
FROM public.attention_request_state
WHERE account_id = @u AND beacon_id = @b
'''),
        parameters: {'u': _viewerId, 'b': _earlyBeaconId},
      );
      expect(rows, hasLength(1));
      expect(
        (rows.single[0]! as DateTime).toUtc().toIso8601String(),
        '2026-08-10T09:00:00.000Z',
        reason:
            'the anchor is when the Request entered, so a fixture or an '
            'import whose forward predates the row still sorts by the event '
            'and not by the wall clock of the write',
      );
    });

    test('a Request whose anchor row is missing still sorts stably', () async {
      await _forwardEdge(
        writer,
        id: 'FEord10',
        beaconId: _lateBeaconId,
        createdAt: '2026-08-10T10:00:00Z',
      );
      await _forwardEdge(
        writer,
        id: 'FEord11',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      // The hole the scout warned about: a legacy row that never went
      // through the U09a trigger.
      await writer.execute(
        Sql.named('''
DELETE FROM public.attention_request_state
WHERE account_id = @u AND beacon_id = @b
'''),
        parameters: {'u': _viewerId, 'b': _earlyBeaconId},
      );

      final page = await query.activityOffers(accountId: _viewerId);
      expect(page.items.map((row) => row.beaconId).toList(), [
        _lateBeaconId,
        _earlyBeaconId,
      ]);
      expect(
        page.items.last.listPositionAt.toUtc().toIso8601String(),
        '2026-08-10T09:00:00.000Z',
        reason: 'the documented fallback is latest_forward_at, which for an '
            'un-re-forwarded Request is its entry',
      );
    });

    // ------------------------------------------------------- pagination

    test('a Request gaining an optional event mid-pagination is not duplicated',
        () async {
      for (var index = 0; index < 6; index++) {
        await _profile(
          writer,
          id: 'Nordpg$index',
          createdAt: '2026-08-0${index + 1}T12:00:00Z',
        );
      }
      await _forwardEdge(
        writer,
        id: 'FEord12',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-02T09:00:00Z',
      );
      await _watching(writer, beaconId: _earlyBeaconId);

      final first = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        limit: 3,
      );
      final cursor = first.page.nextCursor!;

      // Mid-pagination, an optional event lands on the Request that is still
      // below the cursor. Under the old key it would jump to the head and be
      // read twice — once from the head page the client already holds and
      // once from the tail it is about to request.
      await _optional(
        writer,
        id: 'Nordbump',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-30T12:00:00Z',
      );

      final second = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        cursor: cursor,
        limit: 10,
      );
      final ids = [
        ...first.page.items.map((item) => item.id),
        ...second.page.items.map((item) => item.id),
      ];
      expect(ids.toSet(), hasLength(ids.length), reason: 'no duplicate');
      expect(
        ids,
        contains('inbox:$_earlyBeaconId'),
        reason: 'and it did not vanish either',
      );
      expect(ids.where((id) => id.startsWith('Nordpg')).toSet(), hasLength(6));
    });

    test('a promoted Request does not vanish between pages', () async {
      for (var index = 0; index < 6; index++) {
        await _profile(
          writer,
          id: 'Nordvan$index',
          createdAt: '2026-08-0${index + 1}T12:00:00Z',
        );
      }
      await _forwardEdge(
        writer,
        id: 'FEordRA3',
        beaconId: _earlyBeaconId,
        createdAt: '2026-07-30T09:00:00Z',
      );
      await _detachInbox(writer, beaconId: _earlyBeaconId);
      await _optional(
        writer,
        id: 'Nordvan10',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-01T09:00:00Z',
      );

      final first = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        limit: 3,
      );
      final cursor = first.page.nextCursor!;

      await _optional(
        writer,
        id: 'Nordvan11',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-30T09:00:00Z',
      );

      final second = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        cursor: cursor,
        limit: 10,
      );
      final ids = [
        ...first.page.items.map((item) => item.id),
        ...second.page.items.map((item) => item.id),
      ];
      expect(
        ids,
        contains('activity-beacon:$_earlyBeaconId'),
        reason:
            'the group is anchored below the cursor and stays there, so the '
            'reader still reaches it; a bumping key would have lifted it '
            'above the cursor where this reader can never look again',
      );
      expect(ids.toSet(), hasLength(ids.length));
    });

    test('head refresh and the tail page name the same Request identically',
        () async {
      for (var index = 0; index < 6; index++) {
        await _profile(
          writer,
          id: 'Nordhd$index',
          createdAt: '2026-08-0${index + 1}T12:00:00Z',
        );
      }
      await _forwardEdge(
        writer,
        id: 'FEord13',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-02T09:00:00Z',
      );
      await _watching(writer, beaconId: _earlyBeaconId);

      final first = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        limit: 3,
      );
      final cursor = first.page.nextCursor!;
      await _optional(
        writer,
        id: 'Nordhd10',
        beaconId: _earlyBeaconId,
        createdAt: '2026-08-30T12:00:00Z',
      );

      final tail = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        cursor: cursor,
        limit: 10,
      );
      final head = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
        limit: 10,
      );
      final tailRow = tail.page.items
          .where((item) => item.beaconId == _earlyBeaconId)
          .single;
      final headRow = head.page.items
          .where((item) => item.beaconId == _earlyBeaconId)
          .single;
      expect(
        headRow.id,
        tailRow.id,
        reason:
            'a grouped row is named after its Request, so merging a head '
            'refresh into held pages reconciles by Request id exactly — D08',
      );
      expect(headRow.createdAt, tailRow.createdAt);
    });
  }, skip: skipReason);
}

const _viewerId = 'Uord01';
const _authorId = 'Uord02';
const _secondSenderId = 'Uord03';
const _ownedBeaconId = 'Bordowned';
const _owned2BeaconId = 'Bordownee';
const _earlyBeaconId = 'Bordearly';
const _lateBeaconId = 'Bordlate';

Future<void> _clearReceipt(Connection writer, String id) => writer.execute(
      Sql.named('''
UPDATE public.notification_outbox
SET cleared_at = now(), clear_reason = 'explicit'
WHERE id = @id
'''),
      parameters: {'id': id},
    );

Future<void> _watching(Connection writer, {required String beaconId}) =>
    writer.execute(
      Sql.named('''
UPDATE public.inbox_item SET status = 1
WHERE user_id = @u AND beacon_id = @b
'''),
      parameters: {'u': _viewerId, 'b': beaconId},
    );

Future<void> _forwardEdge(
  Connection writer, {
  required String id,
  required String beaconId,
  String createdAt = '2026-08-10T10:00:00Z',
  String senderId = _authorId,
}) =>
    writer.execute(
      Sql.named('''
INSERT INTO public.beacon_forward_edge (
  id, beacon_id, sender_id, recipient_id, created_at, cancelled_at
) VALUES (@id, @beaconId, @authorId, @viewerId, CAST(@createdAt AS timestamptz), NULL)
'''),
      parameters: {
        'id': id,
        'beaconId': beaconId,
        'authorId': senderId,
        'viewerId': _viewerId,
        'createdAt': createdAt,
      },
    );

/// A Request whose Activity events have no representative row: the forward
/// that authorized the viewer to see them is gone from the inbox, so the feed
/// synthesises a `requestActivity` group. This is the shape with **no**
/// `first_entry_at` at all.
Future<void> _detachInbox(Connection writer, {required String beaconId}) =>
    writer.execute(
      Sql.named('''
DELETE FROM public.inbox_item WHERE user_id = @u AND beacon_id = @b
'''),
      parameters: {'u': _viewerId, 'b': beaconId},
    );

Future<void> _optional(
  Connection writer, {
  required String id,
  required String beaconId,
  String createdAt = '2026-07-16T12:00:00Z',
}) =>
    writer.execute(
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

Future<void> _profile(
  Connection writer, {
  required String id,
  String createdAt = '2026-07-16T12:00:00Z',
}) =>
    writer.execute(
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

Future<void> _obligation(
  Connection writer, {
  required String id,
  required String beaconId,
  String createdAt = '2026-07-16T12:00:00Z',
}) =>
    writer.execute(
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
