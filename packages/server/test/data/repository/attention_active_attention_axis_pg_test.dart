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
import 'package:tentura_server/data/repository/attention_sweep_repository.dart';
import 'package:tentura_server/domain/attention/attention_clear_models.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';

import '../../support/attention_axis_contract.dart';
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
  // U15R-d — the contract loop, closed from the server side. The numbers this
  // file produces are the ones `docs/contracts/attention-active-attention-
  // axis.json` records and the client drives its own expectations from. Until
  // now only the client opened the file, so a change here could move a total
  // and leave the contract describing the old one.
  final contract = AttentionAxisContract.load();

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
    late AttentionSweepRepository sweep;

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
      clear = AttentionClearRepository(database);
      sweep = AttentionSweepRepository(database);
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

      final recorded = contract.axisCase('seen but uncleared optional receipt');
      expect(
        summary.myWorkUnreadTotal,
        recorded.myWorkUnreadTotal,
        reason: 'reading is not clearing (D02): seen_at must not decide the dot',
      );
      expect(summary.myDeskDot, recorded.myDeskDot);
      expect(summary.forYouDot, recorded.forYouDot);
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

      final recorded = contract.axisCase('unseen but cleared optional receipt');
      expect(summary.myWorkUnreadTotal, recorded.myWorkUnreadTotal);
      expect(summary.myDeskDot, recorded.myDeskDot);
      expect(summary.forYouDot, recorded.forYouDot);
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
      final recorded = contract.axisCase(
        'a live obligation is active attention even when seen',
      );
      expect(summary.needsYouTotal, recorded.needsYouTotal);
      expect(
        summary.myWorkUnreadTotal,
        recorded.myWorkUnreadTotal,
        reason:
            'active attention = uncleared optional ∪ live obligation; a live '
            'obligation must not fall out of the default list total',
      );
      expect(
        summary.myDeskDot,
        recorded.myDeskDot,
        reason: '§6 keeps the obligation out of the dot — it is the number',
      );
      expect(summary.forYouDot, recorded.forYouDot);
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
      final recorded = contract.axisCase(
        'a settled obligation stops being active attention',
      );
      expect(summary.needsYouTotal, recorded.needsYouTotal);
      expect(summary.myWorkUnreadTotal, recorded.myWorkUnreadTotal);
      expect(summary.myDeskDot, recorded.myDeskDot);
      expect(summary.forYouDot, recorded.forYouDot);
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

    // REWRITTEN IN U15R-a (was: "…leaves My Work", asserted as an empty
    // projection). The axis guarantee is unchanged and is what is asserted
    // here: a cleared optional set stops counting, stops previewing, and the
    // Request has nothing to act on. What changed is that the row itself
    // stays — emitting nothing also threw away the Request's ordering anchor,
    // so the card jumped (R8). Quiet is not the same as gone.
    test('a Request whose whole optional set is cleared goes quiet on My Work',
        () async {
      await _optional(writer, id: 'Naxis06', beaconId: _ownedBeaconId);
      await _clearReceipt(writer, 'Naxis06');

      final rows = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId},
      );
      expect(rows.single.unseenCount, 0);
      expect(rows.single.latestUnseen, isNull);
      expect(rows.single.liveObligations, isEmpty);
      expect(rows.single.needsYouAt, isNull);
      expect(rows.single.firstEntryAt, isNotNull);
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

    // ------------------------------------------------------- U15R-d (§6)

    // The §6 indicator rules, as their own fields. The legacy three
    // (`activityUnreadTotal`, `myWorkUnreadTotal`, `needsYouTotal`) are NOT
    // any of them and are deliberately left computing what they always did
    // until U18 retires them, so nothing below re-states their meaning.

    test('U15R-d §6 my desk.dot — an obligation-only Request does not light '
        'the optional dot', () async {
      await _obligation(writer, id: 'Nd01', beaconId: _ownedBeaconId);

      final summary = await query.surfaceSummary(accountId: _viewerId);
      expect(
        summary.myDeskDot,
        isFalse,
        reason:
            '§6: request.dot = uncleared optional event or uncleared outcome. '
            'An obligation is the *number*; dot and count are independent '
            '(D09), so an obligation alone must not raise the dot.',
      );
      expect(
        summary.myWorkUnreadTotal,
        1,
        reason:
            'the legacy union field is unchanged by this unit and still '
            'counts the obligation — it retires in U18',
      );
    });

    test('U15R-d §6 my desk.dot — an uncleared optional event on an owned '
        'Request lights it, clearing puts it out', () async {
      await _optional(writer, id: 'Nd02', beaconId: _ownedBeaconId);
      await _markSeen(writer, 'Nd02');

      expect(
        (await query.surfaceSummary(accountId: _viewerId)).myDeskDot,
        isTrue,
        reason: 'reading is not clearing (D02)',
      );

      await _clearReceipt(writer, 'Nd02');
      expect(
        (await query.surfaceSummary(accountId: _viewerId)).myDeskDot,
        isFalse,
      );
    });

    test('U15R-d §6 my desk.dot — an uncleared outcome on an owned Request '
        'lights it', () async {
      // A forward edge on the viewer's own Request materialises an
      // `inbox_item` inside the responsibility scope: Set O membership with
      // no optional receipt anywhere.
      await _forwardEdge(writer, id: 'FEd01', beaconId: _ownedBeaconId);

      final summary = await query.surfaceSummary(accountId: _viewerId);
      expect(
        summary.myDeskDot,
        isTrue,
        reason: '§6 request.dot counts an uncleared *outcome* too, not only '
            'optional events',
      );
    });

    test('U15R-d §6 for you.dot — a dismissible Activity receipt lights it, '
        'a swept one does not', () async {
      await _profile(writer, id: 'Nd03');

      expect(
        (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
        isTrue,
      );

      await _clearReceipt(writer, 'Nd03');
      expect(
        (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
        isFalse,
        reason: 'the tab that lights with nothing to act on is the failure M1 '
            'exists to prevent',
      );
    });

    test('U15R-d §6 for you.dot — a pending forward lights it with no receipt '
        'at all', () async {
      await _forwardEdge(writer, id: 'FEd02', beaconId: _foreignBeaconId);

      final summary = await query.surfaceSummary(accountId: _viewerId);
      expect(
        summary.forYouDot,
        isTrue,
        reason:
            '§6 for you.dot = dismissible attention, pending forward or '
            'pending prompt — the pinned zone is a term of its own',
      );
      expect(
        summary.activityUnreadTotal,
        0,
        reason: 'the legacy field never saw the pinned zone; that omission is '
            'exactly what the new field fixes',
      );
    });

    test('U15R-d §6 for you.dot — a timeline_only dismissible does not light '
        'the tab it cannot be reached from', () async {
      // The placement leg of the Set R term, pinned by behaviour rather than
      // by re-reading the SQL. `timeline_only` is in Set R — the sweep may
      // dismiss it — but it is excluded from every primary-surface indicator
      // (m0189/D16), so a dot lit by one would be §6's "tab that lights up
      // and then shows nothing to act on".
      await _timelineOnlySetRReceipt(writer, id: 'Nd07');

      expect(
        (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
        isFalse,
        reason: 'whatever is counted must be reachable (§6, One predicate)',
      );

      // The control: the same fixture on the primary surface does light it,
      // so the assertion above is about `placement` and nothing else.
      await _profile(writer, id: 'Nd08');
      expect(
        (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
        isTrue,
        reason: 'and the fixture is otherwise a Set R member that lights it',
      );
    });

    test('U15R-d M1 — for you.dot equals the composed membership of Set R, '
        'Set O and the pinned zone', () async {
      await _forwardEdge(writer, id: 'FEd03', beaconId: _foreignBeaconId);
      await _optional(writer, id: 'Nd04', beaconId: _foreignBeaconId);
      await _profile(writer, id: 'Nd05');

      // Never a hand-counted number and never a feed length: the indicator is
      // compared to the *same* predicates the lists and the sweep compose —
      // literally the same, since U15R-d's verify pass caught this helper
      // composing its own copy of the rule with the Set R placement filter
      // missing. A guard that spells the predicate slightly differently from
      // production cannot catch production drifting; both now read
      // `AttentionDismissibleSql.forYouDotExpression`.
      expect(
        (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
        await _composedForYouMembership(writer),
      );

      await _clearReceipt(writer, 'Nd04');
      await _clearReceipt(writer, 'Nd05');
      expect(
        (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
        await _composedForYouMembership(writer),
        reason: 'still one rule after a clear moves half of it',
      );

      // Emptying the pinned zone: the row is removed, not dismissed. A
      // trigger refuses `tombstone_dismissed_at` on an unanswered forward —
      // owner decision A enforced in the database, which is the point of the
      // exclusion this dot composes.
      await writer.execute(
        Sql.named('DELETE FROM public.inbox_item WHERE user_id = @u'),
        parameters: {'u': _viewerId},
      );
      expect(
        (await query.surfaceSummary(accountId: _viewerId)).forYouDot,
        await _composedForYouMembership(writer),
        reason: 'and after the pinned zone empties',
      );
    });

    test('U15R-e — a Request-less live obligation is rejected by '
        'notification_outbox__obligation_beacon_chk', () async {
      // The inverse of the U15R-d contract gap. U15R-d proved the shape was
      // storable — `notification_outbox__beacon_policy_chk` demands a
      // `beacon_id` only for the `beacon_content` / `beacon_tombstone`
      // access policies — and that `visibleWithSurface` then labelled it
      // `activity`, where §6 offers it neither a count nor a dot term. That
      // is what stopped `my desk.count` from being scoped to myWork.
      //
      // m0191 closes it in storage rather than by widening a predicate or
      // inventing a §6 term: `AttentionPolicy.logicalTaskKey` already throws
      // `Live obligation requires a Request` on every dispatched receipt, so
      // the constraint states the producer's own rule where nothing can route
      // around it.
      //
      // Asserted **by constraint name**, per U04: a test that only checks
      // "the insert failed" passes when it fails for an unrelated reason —
      // a typo in the fixture, a missing column, a dedup collision.
      await expectLater(
        _beaconlessObligation(writer, id: 'Ne06'),
        throwsA(
          isA<ServerException>().having(
            (error) => error.constraintName,
            'constraintName',
            'notification_outbox__obligation_beacon_chk',
          ),
        ),
      );

      // The control: the same fixture *with* a Request stores, so the
      // rejection above is about the missing `beacon_id` and not about any
      // other column the fixture sets.
      await _obligation(writer, id: 'Ne06ok', beaconId: _ownedBeaconId);
      final stored = await _idsWith(
        writer,
        AttentionDismissibleSql.visibleWithSurface,
        AttentionDismissibleSql.liveObligation('v'),
      );
      expect(stored, ['Ne06ok']);
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
      await _forwardEdge(writer, id: 'FEaxis04', beaconId: _otherBeaconId);
      await _optional(writer, id: 'Naxis15', beaconId: _otherBeaconId);
      // The forward edge is what makes the Request readable; deleting the
      // inbox row it materialises removes the eligible representative, so the
      // event has nothing to coalesce onto but `requestActivity`.
      await writer.execute(
        Sql.named(
          'DELETE FROM public.inbox_item WHERE user_id = @u AND beacon_id = @b',
        ),
        parameters: {'u': _viewerId, 'b': _otherBeaconId},
      );

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
        [_foreignBeaconId, _otherBeaconId],
        reason:
            'REWRITTEN IN U10c, and this is the one expectation in the plan '
            'that flips because a defect was fixed rather than because '
            'behaviour was redefined. U10b pinned the live (wrong) order '
            '[other, foreign] with its reasoning written out: the pinned sort '
            'key was still GREATEST(latest_forward_at, max child created_at), '
            'so an optional arrival moved the zone, which §6 forbids. U10c '
            'separated the position key from the latest-event key, so the '
            'arrival now changes a dot, a preview and an event list and '
            'nothing else — the order is the one from before it arrived.',
      );
      expect(beforeOrder, [_foreignBeaconId, _otherBeaconId]);

      await _clearReceipt(writer, 'Naxis16');
      final afterClear = await query.activityOffers(accountId: _viewerId);
      expect(
        afterClear.items.map((row) => row.beaconId).toList(),
        afterArrival.items.map((row) => row.beaconId).toList(),
        reason:
            'U10b narrowed what counts as an event; that narrowing is '
            'invisible to the pinned order — and since U10c the arrival is '
            'too, so all three readings are the same order',
      );
      expect(afterClear.items.map((row) => row.beaconId).toSet(), {
        _foreignBeaconId,
        _otherBeaconId,
      });
    });

    // ------------------------------- round trip: the sweep and undo legs
    //
    // U10b asserted the *clear* leg against the projections. The circuit the
    // last four units exist to close is U08 writes → U09 sweeps → U09c undoes
    // → U10b projects, and two thirds of it was never asserted end to end: a
    // sweep that wrote `cleared_at` and a feed that ignored it would have
    // passed every test in this file. The three legs below run the real
    // repositories, never a hand-written UPDATE, and check all three read
    // shapes each time — the surface summary (the dot), the default unread
    // feed (the list) and the Activity grouping (the cards).

    test('a sweep empties the summary, the feed and the grouping together',
        () async {
      await _forwardEdge(writer, id: 'FEaxis05', beaconId: _foreignBeaconId);
      await _optional(writer, id: 'Naxis18', beaconId: _foreignBeaconId);
      await _profile(writer, id: 'Naxis19');
      await _optional(writer, id: 'Naxis20', beaconId: _ownedBeaconId);

      final before = await _activityShape(query);
      expect(before.summaryTotal, 2, reason: 'two active optional rows on the '
          'Activity surface; the My Desk row is a different surface');
      expect(before.feedIds, isNotEmpty);
      expect(before.offerUnseen[_foreignBeaconId], 1);

      final result = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPaxis18',
      );
      expect(
        result.appliedReceiptIds.toSet(),
        {'Naxis18', 'Naxis19'},
        reason: 'the sweep clears the Activity optional rows and nothing else',
      );

      final after = await _activityShape(query);
      expect(
        after.summaryTotal,
        0,
        reason: 'U09 wrote cleared_at; the dot is supposed to read it',
      );
      expect(after.feedIds, isEmpty);
      expect(
        after.offerUnseen[_foreignBeaconId],
        0,
        reason: 'the grouping is the third read shape and moves with the '
            'other two — a card still showing a swept count is M1 failing on '
            'the grouped surface',
      );
      expect(
        (await query.surfaceSummary(accountId: _viewerId)).myWorkUnreadTotal,
        1,
        reason: 'My Desk is not dismissible from For You (Set R)',
      );
    });

    test('undo brings the summary, the feed and the grouping back', () async {
      await _forwardEdge(writer, id: 'FEaxis06', beaconId: _foreignBeaconId);
      await _optional(writer, id: 'Naxis21', beaconId: _foreignBeaconId);
      await _profile(writer, id: 'Naxis22');

      final before = await _activityShape(query);
      final result = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPaxis21',
      );
      expect(result.undoToken, isNotNull);
      expect((await _activityShape(query)).summaryTotal, 0);

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: 'OPaxis21',
        undoToken: result.undoToken!,
      );
      expect(undone.restoredReceiptIds.toSet(), {'Naxis21', 'Naxis22'});

      final after = await _activityShape(query);
      expect(
        after.summaryTotal,
        before.summaryTotal,
        reason: 'undo un-writes cleared_at; every projection that fell to the '
            'sweep has to come back, or the window is not an undo',
      );
      expect(after.feedIds, before.feedIds);
      expect(after.offerUnseen, before.offerUnseen);
    });

    test('neither the sweep nor its undo touches the pinned zone', () async {
      // Owner decision A: *Dismiss all* never clears anything awaiting a
      // decision. An unanswered forward is awaiting one, so the pinned card
      // must survive the sweep with its question intact — and survive the
      // undo without being duplicated or reordered.
      await _forwardEdge(
        writer,
        id: 'FEaxis07',
        beaconId: _foreignBeaconId,
        createdAt: '2026-08-10T10:00:00Z',
      );
      await _forwardEdge(
        writer,
        id: 'FEaxis08',
        beaconId: _otherBeaconId,
        createdAt: '2026-08-10T09:00:00Z',
      );
      await _optional(writer, id: 'Naxis23', beaconId: _foreignBeaconId);

      final before = await query.activityOffers(accountId: _viewerId);
      final beforeOrder = before.items.map((row) => row.beaconId).toList();
      expect(beforeOrder, hasLength(2));

      final result = await sweep.dismissAll(
        accountId: _viewerId,
        operationId: 'OPaxis23',
      );
      expect(
        result.appliedOutcomeBeaconIds,
        isEmpty,
        reason: 'both Requests are unanswered forwards in the pinned zone; '
            'the outcome axis must refuse every one of them (decision A)',
      );

      final afterSweep = await query.activityOffers(accountId: _viewerId);
      expect(afterSweep.items.map((row) => row.beaconId).toList(), beforeOrder);
      expect(afterSweep.totalCount, before.totalCount);

      final undone = await sweep.undo(
        accountId: _viewerId,
        operationId: 'OPaxis23',
        undoToken: result.undoToken!,
      );
      expect(undone.restoredOutcomeBeaconIds, isEmpty);

      final afterUndo = await query.activityOffers(accountId: _viewerId);
      expect(afterUndo.items.map((row) => row.beaconId).toList(), beforeOrder);
      expect(afterUndo.totalCount, before.totalCount);
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
        decisionRevision: capture.decisionRevision,
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
      final projection = await query.myWorkAttention(
        accountId: _viewerId,
        beaconIds: {_ownedBeaconId},
      );
      expect(
        projection.single.unseenCount,
        0,
        reason:
            'U08 wrote cleared_at, U10b reads it: the clear command and the '
            'projections it is supposed to empty now agree end to end',
      );
      expect(
        projection.single.latestUnseen,
        isNull,
        reason: 'nothing is left to preview',
      );
    });
  }, skip: skipReason);

  group('U15R-d — the contract is read from both ends', () {
    test('the recorded predicates still match the server source', () {
      // The client asserts this from its side already. Asserting it here too
      // is the whole point of the unit: the file the client trusts is written
      // from *this* package, so the package that can invalidate it has to be
      // the one that checks.
      AttentionAxisContract.load().assertMatchesServerSql();
    });

    test('every axis case records the §6 indicator fields', () {
      for (final entry in AttentionAxisContract.load().axisCases) {
        final axisCase = AttentionAxisCase(entry);
        expect(
          () => (axisCase.myDeskDot, axisCase.forYouDot),
          returnsNormally,
          reason:
              'a case without the §6 dots is a case the PG tests cannot drive '
              'from the contract, which is how the loop reopens',
        );
      }
    });
  });

  group('U10b — structurally one definition', () {
    // The guard is stated over the *directory*, not over a list of the files
    // already caught. U10a found copies three and four, U10b a fifth spelling
    // in the clear command, and this remediation a sixth in the sweep's apply
    // UPDATE. Every one of them was in a file no existing guard named. A guard
    // that only covers what has already been fixed cannot prevent the next
    // one, so the rule is: no attention repository spells the axis by hand,
    // including files that do not exist yet.
    test('no attention repository spells the axis out by hand', () {
      const home = 'lib/data/repository/attention_dismissible_sql.dart';
      final offenders = <String>[];
      for (final entity
          in Directory('lib/data/repository').listSync(recursive: true)) {
        if (entity is! File) continue;
        final path = entity.path.replaceAll(r'\', '/');
        if (!path.contains('/attention_') || !path.endsWith('.dart')) continue;
        if (path.endsWith(home)) continue;
        if (entity.readAsStringSync().contains('cleared_at IS NULL')) {
          offenders.add(path);
        }
      }
      expect(
        offenders,
        isEmpty,
        reason:
            'the active-attention predicate lives in AttentionDismissibleSql '
            '($home) and is composed via activeOptional/activeAttention. '
            'A hand-written copy is how the indicator, its list and the '
            'operations that are supposed to empty them drift apart (M1).',
      );
    });
  });
}

/// The three Activity read shapes, read together so a leg of the round trip
/// cannot be asserted on one of them and silently skipped on the others.
typedef _ActivityShape = ({
  int summaryTotal,
  List<String> feedIds,
  Map<String, int> offerUnseen,
});

Future<_ActivityShape> _activityShape(AttentionRepository query) async {
  final summary = await query.surfaceSummary(accountId: _viewerId);
  final feed = await query.attentionFeed(
    accountId: _viewerId,
    view: AttentionFeedView.unread,
    surface: AttentionSurface.activity,
  );
  final offers = await query.activityOffers(accountId: _viewerId);
  return (
    summaryTotal: summary.activityUnreadTotal,
    feedIds: [for (final item in feed.page.items) item.id],
    offerUnseen: {
      for (final row in offers.items) row.beaconId: row.eventUnseenCount,
    },
  );
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

/// A dismissible Set R receipt that is **not** on the primary surface.
///
/// Built on [_profile] deliberately: that is the fixture the sibling test
/// proves lights `for you.dot`, so flipping only `placement` isolates the one
/// variable. An `_optional` on a foreign Request looks like the natural
/// fixture and is not — the viewer cannot read that beacon's content, so the
/// row never reaches `visible` and the assertion passes for the wrong reason.
/// (It did, until the mutation check caught it.)
///
/// `timeline_only` (m0189/D16) is visible and recoverable but excluded from
/// every primary-surface indicator, so child activity never lights an ancestor
/// Request. It is still a member of Set R — the sweep may dismiss it — which
/// is exactly why the dot has to ask about placement separately.
Future<void> _timelineOnlySetRReceipt(
  Connection writer, {
  required String id,
}) async {
  await _profile(writer, id: id);
  await writer.execute(
    Sql.named(
      "UPDATE public.notification_outbox SET placement = 'timeline_only' "
      'WHERE id = @id',
    ),
    parameters: {'id': id},
  );
}

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

/// Set R ∪ Set O ∪ the pinned zone, composed from the same constants the
/// lists and the sweep compose. The M1 comparison target for `forYouDot`.
Future<bool> _composedForYouMembership(Connection writer) async {
  final rows = await writer.execute(
    Sql.named(
      '''
WITH ${AttentionDismissibleSql.cte}
SELECT (${AttentionDismissibleSql.forYouDotExpression}) AS member
'''
          .replaceAll(r'$1', '@account'),
    ),
    parameters: {'account': _viewerId},
  );
  return rows.single[0]! as bool;
}

/// A live obligation with no Request — the shape m0191 makes unstorable.
///
/// Kept as a fixture precisely because it is rejected: the U15R-e test drives
/// it at the database to assert the rejection by constraint name.
Future<void> _beaconlessObligation(
  Connection writer, {
  required String id,
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
  'Obligation', 'Body', '/profile', @dedupKey, now(),
  NULL, @sourceEventKey,
  'profile', 'invite_accepted', '{"eventType":"fixture"}'::jsonb,
  'standard', 'profile',
  true, @threadKey
)
'''),
      parameters: {
        'id': id,
        'accountId': _viewerId,
        'dedupKey': 'dedup-$id',
        'sourceEventKey': 'source-$id',
        'threadKey': 'v1|needsMe|$id|$_viewerId',
      },
    );
