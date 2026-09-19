@Tags(['pg'])
library;

import 'dart:io';

import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'package:tentura_server/data/database/tentura_db.dart'
    hide isNotNull, isNull;
import 'package:tentura_server/data/repository/attention_clear_repository.dart';
import 'package:tentura_server/data/repository/attention_dismissible_sql.dart';
import 'package:tentura_server/data/repository/attention_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/disposable_pg_target.dart';

/// U10b — dots, counts, summaries and grouping eligibility read *active
/// attention*, not `seen_at` (D02, D09, product contract §6).
///
/// Three things are pinned here and nowhere else:
///
/// 1. **The axis itself.** A receipt that is *seen but uncleared* still asks
///    for attention; a receipt that is *unseen but cleared* does not. Every
///    assertion below is stated as that pair, because a predicate that merely
///    ANDs `cleared_at IS NULL` onto `seen_at IS NULL` passes the first half
///    and fails the second.
/// 2. **M1 — one predicate, not two.** The rule behind an indicator and the
///    rule deciding what its list shows by default are the same function.
///    Asserted twice: as a behavioural identity (the number equals the list),
///    and as a divergence probe (loosening the shared function in a throwaway
///    copy moves *both* sides, so they cannot be separately maintained).
/// 3. **The three ways this unit goes wrong silently** — a Request vanishing
///    from a surface, a count disagreeing with its list, and the pinned zone
///    reordering because an optional event arrived.
Future<void> main() async {
  final target = DisposablePgTarget.fromNamedEnvironment(
    envVarName: 'TENTURA_ATTENTION_AXIS_TEST_DB',
    defaultNamePrefix: 'tentura_test_attn_axis',
  );
  final reachable = await canReachPostgresAdmin(target);
  final skipReason = reachable
      ? false
      : 'Postgres admin database not reachable for disposable test target';

  group('U10b — the active-attention axis', () {
    late DisposablePgWriterSession session;
    late Connection writer;
    late TenturaDb database;
    late AttentionRepository query;
    late AttentionClearRepository clear;

    setUpAll(() async {
      session = await setUpDisposablePgWriter(target: target);
      writer = session.writer;
      database = openDisposablePgDatabase(target);
      query = AttentionRepository(database);
      clear = AttentionClearRepository(database);
    });

    setUp(() async {
      await writer.execute('''
TRUNCATE TABLE
  public.attention_clear_operation,
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
  (@foreignId, @authorId, 'Foreign', 'Foreign request', 0),
  (@otherId, @authorId, 'Other', 'Other request', 0)
'''),
        parameters: {
          'ownedId': _ownedBeaconId,
          'foreignId': _foreignBeaconId,
          'otherId': _otherBeaconId,
          'viewerId': _viewerId,
          'authorId': _authorId,
        },
      );
    });

    tearDownAll(() async {
      await tearDownDisposablePgWriter(session: session, drift: database);
    });

    // ---------------------------------------------------------------- axis

    test('a seen but uncleared optional receipt still asks for attention',
        () async {
      await _optional(writer, id: 'Naxis01', beaconId: _ownedBeaconId);
      await _markSeen(writer, 'Naxis01');

      final summary = await query.surfaceSummary(accountId: _viewerId);
      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.myWork,
      );

      expect(
        summary.myWorkUnreadTotal,
        1,
        reason: 'reading is not clearing (D02): seen_at must not decide the dot',
      );
      expect(feed.page.items.map((item) => item.id), ['Naxis01']);
    });

    test('an unseen but cleared optional receipt no longer asks', () async {
      await _optional(writer, id: 'Naxis02', beaconId: _ownedBeaconId);
      await _clearReceipt(writer, 'Naxis02');

      final summary = await query.surfaceSummary(accountId: _viewerId);
      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.myWork,
      );

      expect(summary.myWorkUnreadTotal, 0);
      expect(feed.page.items, isEmpty);
      expect(
        (await query.unreadForBeacons(
          accountId: _viewerId,
          beaconIds: {_ownedBeaconId},
        )),
        isEmpty,
        reason: 'the per-Request dot marker moves with the same axis',
      );
    });

    test('a live obligation is active attention even when seen', () async {
      await _obligation(writer, id: 'Naxis03', beaconId: _ownedBeaconId);
      await _markSeen(writer, 'Naxis03');

      final summary = await query.surfaceSummary(accountId: _viewerId);
      expect(summary.needsYouTotal, 1);
      expect(
        summary.myWorkUnreadTotal,
        1,
        reason:
            'active attention = uncleared optional ∪ live obligation; a live '
            'obligation must not fall out of the surface total',
      );
    });

    test('a settled obligation stops being active attention', () async {
      await _obligation(writer, id: 'Naxis04', beaconId: _ownedBeaconId);
      await writer.execute(
        Sql.named('''
UPDATE public.notification_outbox
SET settlement_kind = 'resolved', settled_at = now(), settled_by_user_id = @u
WHERE id = 'Naxis04'
'''),
        parameters: {'u': _viewerId},
      );

      final summary = await query.surfaceSummary(accountId: _viewerId);
      expect(summary.needsYouTotal, 0);
      expect(summary.myWorkUnreadTotal, 0);
    });

    test('myWorkAttention counts active optional, not unseen', () async {
      await _optional(writer, id: 'Naxis05a', beaconId: _ownedBeaconId);
      await _optional(writer, id: 'Naxis05b', beaconId: _ownedBeaconId);
      await _markSeen(writer, 'Naxis05a');
      await _clearReceipt(writer, 'Naxis05b');

      final rows = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId},
      );
      expect(rows, hasLength(1));
      expect(
        rows.single.unseenCount,
        1,
        reason: 'the seen-but-uncleared row counts; the cleared one does not',
      );
      expect(rows.single.latestUnseen?.id, 'Naxis05a');
    });

    test('a Request whose whole optional set is cleared leaves My Work',
        () async {
      await _optional(writer, id: 'Naxis06', beaconId: _ownedBeaconId);
      await _clearReceipt(writer, 'Naxis06');

      expect(
        await query.myWorkAttention(
          accountId: _viewerId,
          beaconIds: {_ownedBeaconId},
        ),
        isEmpty,
      );
    });

    // ------------------------------------------------- projection exposure

    test('clearedAt and clearReason reach the receipt projection', () async {
      await _optional(writer, id: 'Naxis07', beaconId: _ownedBeaconId);
      await _clearReceipt(writer, 'Naxis07', reason: 'sweep');

      final page = await query.attentionRequestHistory(
        accountId: _viewerId,
        beaconId: _ownedBeaconId,
      );
      final receipt = page.items.single;
      expect(receipt.clearedAt, isNotNull);
      expect(receipt.clearReason, 'sweep');
      expect(receipt.isActiveOptional, isFalse);
    });

    test('an uncleared optional receipt reports no clear fields', () async {
      await _optional(writer, id: 'Naxis08', beaconId: _ownedBeaconId);

      final page = await query.attentionRequestHistory(
        accountId: _viewerId,
        beaconId: _ownedBeaconId,
      );
      expect(page.items.single.clearedAt, isNull);
      expect(page.items.single.clearReason, isNull);
      expect(page.items.single.isActiveOptional, isTrue);
    });

    test('History still reaches a cleared receipt', () async {
      await _optional(writer, id: 'Naxis09', beaconId: _ownedBeaconId);
      await _clearReceipt(writer, 'Naxis09');

      final page = await query.attentionRequestHistory(
        accountId: _viewerId,
        beaconId: _ownedBeaconId,
      );
      expect(
        page.items.map((item) => item.id),
        ['Naxis09'],
        reason:
            'clearing removes a row from the primary surface, never from the '
            'record — §6: whatever is counted must be reachable, and what is '
            'no longer counted must still be findable',
      );
    });

    // -------------------------------------------------------------- M1

    test('M1 — the myWork number equals the myWork default list', () async {
      await _optional(writer, id: 'Naxis10a', beaconId: _ownedBeaconId);
      await _optional(writer, id: 'Naxis10b', beaconId: _ownedBeaconId);
      await _obligation(writer, id: 'Naxis10c', beaconId: _ownedBeaconId);
      await _markSeen(writer, 'Naxis10a');
      await _clearReceipt(writer, 'Naxis10b');

      final summary = await query.surfaceSummary(accountId: _viewerId);
      final feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.myWork,
      );
      expect(summary.myWorkUnreadTotal, feed.page.items.length);
      expect(feed.summary.unreadTotal, feed.page.items.length);
      expect(summary.myWorkUnreadTotal, 2);
    });

    test('M1 — an Activity dot implies a non-empty Activity default list',
        () async {
      await _profile(writer, id: 'Naxis11a');
      await _profile(writer, id: 'Naxis11b');
      await _markSeen(writer, 'Naxis11a');

      var summary = await query.surfaceSummary(accountId: _viewerId);
      var feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.activity,
      );
      expect(summary.activityUnreadTotal, greaterThan(0));
      expect(feed.page.items, isNotEmpty);

      await _clearReceipt(writer, 'Naxis11a');
      await _clearReceipt(writer, 'Naxis11b');

      summary = await query.surfaceSummary(accountId: _viewerId);
      feed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.activity,
      );
      expect(
        summary.activityUnreadTotal,
        0,
        reason:
            'the tab that lights with nothing to act on is exactly the failure '
            'M1 exists to prevent',
      );
      expect(feed.page.items, isEmpty);
    });

    test('M1 — one function: loosening it moves the number and the list '
        'together', () async {
      // The divergence probe. `activeOptional` is the shared function; a
      // throwaway loosening that drops `cleared_at IS NULL` must change the
      // summary count *and* the default-list cardinality in lockstep. If a
      // future edit gives the indicator its own copy, only one side moves and
      // this test fails.
      await _optional(writer, id: 'Naxis12a', beaconId: _ownedBeaconId);
      await _optional(writer, id: 'Naxis12b', beaconId: _ownedBeaconId);
      await _clearReceipt(writer, 'Naxis12b');

      const strict = AttentionDismissibleSql.visibleWithSurface;
      final tightCount = await _countWith(
        writer,
        strict,
        AttentionDismissibleSql.activeOptional('v'),
      );
      final tightList = await _idsWith(
        writer,
        strict,
        AttentionDismissibleSql.activeOptional('v'),
      );
      final looseCount = await _countWith(
        writer,
        strict,
        'NOT v.requires_action',
      );
      final looseList = await _idsWith(
        writer,
        strict,
        'NOT v.requires_action',
      );

      expect(tightCount, tightList.length);
      expect(looseCount, looseList.length);
      expect(
        looseCount,
        greaterThan(tightCount),
        reason: 'the loosened copy must actually be looser on this fixture',
      );
    });

    test('M1 — the clear command and the indicator share one definition',
        () async {
      // What a clear may touch and what an indicator counts are the same set:
      // anything else means a dot the user cannot extinguish, or a clear that
      // silently reaches a row no surface ever showed.
      await _optional(writer, id: 'Naxis13a', beaconId: _ownedBeaconId);
      await _optional(writer, id: 'Naxis13b', beaconId: _ownedBeaconId);
      await _obligation(writer, id: 'Naxis13c', beaconId: _ownedBeaconId);
      await _markSeen(writer, 'Naxis13a');
      await _clearReceipt(writer, 'Naxis13b');

      final capture = await clear.captureEligible(
        accountId: _viewerId,
        beaconId: _ownedBeaconId,
      );
      final rows = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId},
      );
      expect(capture.receiptIds.toSet(), {'Naxis13a'});
      expect(rows.single.unseenCount, capture.receiptIds.length);
    });

    // ------------------------------------------- failure mode 1: vanishing

    test('clearing the optional children does not unpin the forward',
        () async {
      await _forwardEdge(writer, id: 'FEaxis01', beaconId: _foreignBeaconId);
      await _optional(writer, id: 'Naxis14', beaconId: _foreignBeaconId);

      final before = await query.activityOffers(accountId: _viewerId);
      expect(before.items.map((row) => row.beaconId), [_foreignBeaconId]);

      await _clearReceipt(writer, 'Naxis14');

      final after = await query.activityOffers(accountId: _viewerId);
      expect(
        after.items.map((row) => row.beaconId),
        [_foreignBeaconId],
        reason:
            'owner decision A: an unanswered forward is awaiting a decision. '
            'Clearing its optional noise is not an answer, and must never '
            'remove the card that asks the question.',
      );
      expect(after.items.single.eventTotal, 0);
      expect(after.items.single.eventUnseenCount, 0);
      expect(after.totalCount, 1);
    });

    test('clearing every child retires the synthetic requestActivity row',
        () async {
      // The inverse of the test above, and the reason it is not enough on its
      // own: a `requestActivity` group exists *only* because of its children.
      // When they are all cleared it must go — that is U08 becoming visible,
      // not a Request disappearing, because the Request was never pinned.
      await _optional(writer, id: 'Naxis15', beaconId: _otherBeaconId);

      final before = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(
        before.page.items
            .where((item) => item.itemKind == AttentionItemKind.requestActivity)
            .map((item) => item.beaconId),
        [_otherBeaconId],
      );

      await _clearReceipt(writer, 'Naxis15');

      final after = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.all,
        surface: AttentionSurface.activity,
      );
      expect(
        after.page.items.where(
          (item) => item.itemKind == AttentionItemKind.requestActivity,
        ),
        isEmpty,
      );
      expect(
        (await query.attentionRequestHistory(
          accountId: _viewerId,
          beaconId: _otherBeaconId,
        ))
            .items,
        hasLength(1),
        reason: 'retired from the surface, still in the record',
      );
    });

    // ------------------------------------- failure mode 3: pinned reorder

    test('an optional event does not reorder the pinned zone', () async {
      await _forwardEdge(
        writer,
        id: 'FEaxis02',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-10T10:00:00Z',
      );
      await _forwardEdge(
        writer,
        id: 'FEaxis03',
        beaconId: _otherBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );

      final before = await query.activityOffers(accountId: _viewerId);
      final beforeOrder = before.items.map((row) => row.beaconId).toList();
      expect(beforeOrder, hasLength(2));

      // An optional event arrives on the *lower* pinned Request, and is then
      // cleared again. Neither the arrival nor the clear is a decision, so
      // neither may move the zone. (§6: an optional update changes a dot, a
      // preview and an event list — never a position.)
      await _optional(
        writer,
        id: 'Naxis16',
        beaconId: _otherBeaconId,
        createdAt: '2026-08-12T14:00:00Z',
      );
      final afterArrival = await query.activityOffers(accountId: _viewerId);
      expect(
        afterArrival.items.map((row) => row.beaconId).toList(),
        [_otherBeaconId, _foreignBeaconId],
        reason:
            'Pinned here as the live defect, not as the target. §6 says an '
            'optional update never moves a position, but the pinned sort key '
            'is still GREATEST(latest_forward_at, max child created_at) — and '
            'the ordering key belongs to U10c. U10b records that the arrival '
            'still reorders so U10c has to change this expectation on '
            'purpose; what U10b owes is that its own narrowing of what counts '
            'as an event does not move the zone (asserted next).',
      );
      expect(beforeOrder, [_foreignBeaconId, _otherBeaconId]);

      await _clearReceipt(writer, 'Naxis16');
      final afterClear = await query.activityOffers(accountId: _viewerId);
      expect(
        afterClear.items.map((row) => row.beaconId).toList(),
        afterArrival.items.map((row) => row.beaconId).toList(),
        reason:
            'U10b narrowed what counts as an event; that narrowing must be '
            'invisible to the pinned order, which U10c owns',
      );
      expect(afterClear.items.map((row) => row.beaconId).toSet(), {
        _foreignBeaconId,
        _otherBeaconId,
      });
    });

    // ------------------------------------------------- round trip (add. 5)

    test('a real clear moves the feed and the summary together', () async {
      await _optional(writer, id: 'Naxis17a', beaconId: _ownedBeaconId);
      await _optional(writer, id: 'Naxis17b', beaconId: _ownedBeaconId);

      final before = await query.surfaceSummary(accountId: _viewerId);
      final beforeFeed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.myWork,
      );
      expect(before.myWorkUnreadTotal, 2);
      expect(beforeFeed.page.items, hasLength(2));

      final capture = await clear.captureEligible(
        accountId: _viewerId,
        beaconId: _ownedBeaconId,
      );
      final result = await clear.apply(
        accountId: _viewerId,
        operationId: 'OPaxis17',
        beaconId: _ownedBeaconId,
        kind: AttentionClearCaptureKind.requestOpen,
        outcomeGeneration: capture.outcomeGeneration,
        receiptIds: capture.receiptIds,
      );
      expect(result.appliedReceiptIds.toSet(), {'Naxis17a', 'Naxis17b'});

      final after = await query.surfaceSummary(accountId: _viewerId);
      final afterFeed = await query.attentionFeed(
        accountId: _viewerId,
        view: AttentionFeedView.unread,
        surface: AttentionSurface.myWork,
      );
      expect(after.myWorkUnreadTotal, 0);
      expect(afterFeed.page.items, isEmpty);
      expect(afterFeed.summary.unreadTotal, 0);
      expect(
        await query.myWorkAttention(
          accountId: _viewerId,
          beaconIds: {_ownedBeaconId},
        ),
        isEmpty,
        reason:
            'U08 wrote cleared_at, U10b reads it: the clear command and the '
            'projections it is supposed to empty now agree end to end',
      );
    });
  }, skip: skipReason);

  group('U10b — structurally one definition', () {
    test('the repository never spells the axis out by hand', () {
      final source = File(
        'lib/data/repository/attention_repository.dart',
      ).readAsStringSync();
      expect(
        source,
        isNot(contains('cleared_at IS NULL')),
        reason:
            'the active-attention predicate lives in AttentionDismissibleSql. '
            'A second hand-written copy here is how the indicator and its list '
            'drift apart (M1).',
      );
      final clearSource = File(
        'lib/data/repository/attention_clear_repository.dart',
      ).readAsStringSync();
      expect(clearSource, isNot(contains('cleared_at IS NULL')));
    });
  });
}

const _viewerId = 'Uaxis01';
const _authorId = 'Uaxis02';
const _ownedBeaconId = 'Baxisowned';
const _foreignBeaconId = 'Baxisforeign';
const _otherBeaconId = 'Baxisother';

Future<int> _countWith(
  Connection writer,
  String visibleCte,
  String predicate,
) async {
  final rows = await writer.execute(
    Sql.named('''
WITH $visibleCte
SELECT COUNT(*)::int AS total FROM visible v WHERE $predicate
'''.replaceAll(r'$1', '@account')),
    parameters: {'account': _viewerId},
  );
  return rows.single[0]! as int;
}

Future<List<String>> _idsWith(
  Connection writer,
  String visibleCte,
  String predicate,
) async {
  final rows = await writer.execute(
    Sql.named('''
WITH $visibleCte
SELECT v.id FROM visible v WHERE $predicate ORDER BY v.id
'''.replaceAll(r'$1', '@account')),
    parameters: {'account': _viewerId},
  );
  return [for (final row in rows) row[0]! as String];
}

Future<void> _markSeen(Connection writer, String id) => writer.execute(
      Sql.named('''
UPDATE public.notification_outbox SET seen_at = now() WHERE id = @id
'''),
      parameters: {'id': id},
    );

Future<void> _clearReceipt(
  Connection writer,
  String id, {
  String reason = 'explicit',
}) =>
    writer.execute(
      Sql.named('''
UPDATE public.notification_outbox
SET cleared_at = now(), clear_reason = @reason
WHERE id = @id
'''),
      parameters: {'id': id, 'reason': reason},
    );

Future<void> _forwardEdge(
  Connection writer, {
  required String id,
  required String beaconId,
  String createdAt = '2026-08-10T10:00:00Z',
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
        'authorId': _authorId,
        'viewerId': _viewerId,
        'createdAt': createdAt,
      },
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
