import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart' show PgDateTime;
import 'package:injectable/injectable.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/coordination/filter_beacon_notifications.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/port/attention_settlement_port.dart';

import '../database/tentura_db.dart';
import 'attention_dismissible_sql.dart';

@Singleton(as: AttentionQueryPort)
class AttentionRepository implements AttentionQueryPort {
  const AttentionRepository(this._database);

  final TenturaDb _database;

  static const _authorizedReceiptJoin = '''
FROM public.visible_attention_receipts(\$1) visible
JOIN public.notification_outbox receipt ON receipt.id = visible.receipt_id''';

  @override
  Future<Set<String>> unreadForBeacons({
    required String accountId,
    required Set<String> beaconIds,
  }) async {
    if (beaconIds.isEmpty) return const {};
    final ids = beaconIds.toList(growable: false);
    final placeholders = List.generate(
      ids.length,
      (index) => '\$${index + 2}',
    ).join(',');
    final rows = await _database
        .customSelect(
          '''SELECT DISTINCT receipt.beacon_id
$_authorizedReceiptJoin
WHERE ${AttentionDismissibleSql.activeAttention('receipt')}
  AND ${AttentionDismissibleSql.primaryPlacement('receipt')}
  AND receipt.beacon_id IN ($placeholders)''',
          variables: [
            Variable<String>(accountId),
            ...ids.map(Variable<String>.new),
          ],
        )
        .get();
    return {for (final row in rows) row.read<String>('beacon_id')};
  }

  @override
  Future<Set<String>> liveObligationBeacons({
    required String accountId,
  }) async {
    final rows = await _database
        .customSelect(
          '''SELECT DISTINCT receipt.beacon_id
$_authorizedReceiptJoin
WHERE receipt.requires_action
  AND receipt.settlement_kind IS NULL''',
          variables: [Variable<String>(accountId)],
        )
        .get();
    return {for (final row in rows) row.read<String>('beacon_id')};
  }

  @override
  Future<List<MyWorkBeaconAttention>> myWorkAttention({
    required String accountId,
    required Set<String> beaconIds,
  }) async {
    if (beaconIds.isEmpty) {
      return const [];
    }
    final ids = beaconIds.toList(growable: false);
    final placeholders = List.generate(
      ids.length,
      (index) => '\$${index + 2}',
    ).join(',');
    final rows = await _database
        .customSelect(
          '''
WITH $_visibleWithSurfaceCte,
scoped_beacons AS (
  SELECT scope.beacon_id
  FROM scope
  WHERE scope.beacon_id IN ($placeholders)
),
scoped_receipts AS (
  SELECT v.*
  FROM visible v
  INNER JOIN scoped_beacons sb ON sb.beacon_id = v.beacon_id
  WHERE v.surface = 'myWork'
    -- U11/D16: a propagated hierarchy notice is in the Request's log, not on
    -- My Desk. Excluding it here removes it from the count, from
    -- `latestUnseen`, from `needsYouAt` and from the `firstEntryAt` fallback
    -- in one place — every My Desk key this projection produces.
    AND ${AttentionDismissibleSql.primaryPlacement('v')}
)
SELECT
  scoped_receipts.*,
  state.first_entry_at AS first_entry_at
FROM scoped_receipts
LEFT JOIN public.attention_request_state state
  ON state.account_id = \$1
 AND state.beacon_id = scoped_receipts.beacon_id
ORDER BY beacon_id, created_at DESC, id DESC
''',
          variables: [
            Variable<String>(accountId),
            ...ids.map(Variable<String>.new),
          ],
        )
        .get();

    final byBeacon = <String, List<AttentionReceipt>>{};
    final anchorByBeacon = <String, DateTime>{};
    for (final row in rows) {
      final receipt = _mapRow(row);
      final beaconId = receipt.beaconId;
      if (beaconId == null) {
        continue;
      }
      byBeacon.putIfAbsent(beaconId, () => []).add(receipt);
      final anchor = _readTimestamp(row, 'first_entry_at');
      if (anchor != null) {
        anchorByBeacon[beaconId] = anchor;
      }
    }

    final results = <MyWorkBeaconAttention>[];
    for (final entry in byBeacon.entries) {
      final receipts = entry.value;
      // U10b: the count is active optional attention, not unread receipts.
      // Reading a Request no longer empties My Desk (D02); clearing does.
      final unseenCount = receipts
          .where((receipt) => receipt.isActiveOptional)
          .length;
      final liveObligations = [
        for (final receipt in receipts)
          if (receipt.isLiveObligation) receipt,
      ];
      // U15R-a / R8 — a Request with nothing left to say still keeps its
      // place. `firstEntryAt` is My Desk's stable ordering key; dropping the
      // projection when active attention runs out made the client fall back
      // to `Beacon.createdAt`, so clearing the last event moved the card and
      // the next event moved it back — the bump section 6 forbids, caused by
      // the gesture meant to quieten it. The row is emitted quiet: no count,
      // no preview, no obligations, and the anchor it entered with.
      AttentionReceipt? latestUnseen;
      for (final receipt in receipts) {
        if (receipt.isActiveOptional) {
          latestUnseen = receipt;
          break;
        }
      }
      // U10c, D08 #1 — `Needs you` orders by latest live-obligation
      // creation. An obligation receipt is immutable, so this key only moves
      // when a *new* obligation arrives: the one promotion the contract
      // allows.
      DateTime? needsYouAt;
      for (final obligation in liveObligations) {
        if (needsYouAt == null || obligation.createdAt.isAfter(needsYouAt)) {
          needsYouAt = obligation.createdAt;
        }
      }
      // The stable anchor behind it. `attention_request_state` only has a row
      // where an `inbox_item` does, and an owned Request the viewer was never
      // forwarded has neither — so the documented fallback is the earliest
      // receipt that put the Request on the desk, which is equally immutable.
      final firstEntryAt =
          anchorByBeacon[entry.key] ??
          receipts
              .map((receipt) => receipt.createdAt)
              .reduce((a, b) => a.isBefore(b) ? a : b);
      results.add(
        MyWorkBeaconAttention(
          beaconId: entry.key,
          unseenCount: unseenCount,
          latestUnseen: latestUnseen,
          liveObligations: liveObligations,
          needsYouAt: needsYouAt,
          firstEntryAt: firstEntryAt,
        ),
      );
    }
    results.sort(_compareMyWorkAttention);
    return results;
  }

  /// U10c — the `Needs you` sort key, stated once (D08 #1).
  ///
  /// Latest live obligation first; a Request with none sorts below every
  /// Request that has one, however loud its optional events are. Ties fall
  /// back to first entry and then to the Request id, so the order is total
  /// and does not depend on the row order the database happened to return.
  static int _compareMyWorkAttention(
    MyWorkBeaconAttention a,
    MyWorkBeaconAttention b,
  ) {
    final aNeeds = a.needsYouAt;
    final bNeeds = b.needsYouAt;
    if (aNeeds != null || bNeeds != null) {
      if (aNeeds == null) return 1;
      if (bNeeds == null) return -1;
      final byObligation = bNeeds.compareTo(aNeeds);
      if (byObligation != 0) return byObligation;
    }
    final aEntry = a.firstEntryAt;
    final bEntry = b.firstEntryAt;
    if (aEntry != null && bEntry != null) {
      final byEntry = bEntry.compareTo(aEntry);
      if (byEntry != 0) return byEntry;
    }
    return a.beaconId.compareTo(b.beaconId);
  }

  /// U10a — one predicate source.
  ///
  /// This used to be a second, hand-maintained copy of
  /// `AttentionDismissibleSql.visibleWithSurface`. The two agreed (proved in
  /// `attention_predicate_unification_pg_test.dart`), but only by hand: U10b
  /// moves this definition from `seen_at` to active attention, and a sweep
  /// that kept the old meaning because the projection was edited alone is
  /// exactly the drift the U09a note warned about. Change it there, once.
  static const _visibleWithSurfaceCte =
      AttentionDismissibleSql.visibleWithSurface;

  @override
  Future<AttentionSurfaceSummary> surfaceSummary({
    required String accountId,
  }) async {
    final row = await _database
        .customSelect(
          '''
WITH $_visibleWithSurfaceCte,
summary AS (
  SELECT
    COUNT(*) FILTER (
      WHERE ${AttentionDismissibleSql.activeAttention('v')}
        AND ${AttentionDismissibleSql.primaryPlacement('v')}
        AND v.surface = 'activity'
    )::int AS activity_unread_total,
    COUNT(*) FILTER (
      WHERE ${AttentionDismissibleSql.activeAttention('v')}
        AND ${AttentionDismissibleSql.primaryPlacement('v')}
        AND v.surface = 'myWork'
    )::int AS my_work_unread_total,
    COUNT(*) FILTER (
      WHERE ${AttentionDismissibleSql.liveObligation('v')}
        AND ${AttentionDismissibleSql.primaryPlacement('v')}
    )::int AS needs_you_total
  FROM visible v
)
SELECT * FROM summary
''',
          variables: [Variable<String>(accountId)],
        )
        .getSingle();
    return AttentionSurfaceSummary(
      activityUnreadTotal: row.read<int>('activity_unread_total'),
      myWorkUnreadTotal: row.read<int>('my_work_unread_total'),
      needsYouTotal: row.read<int>('needs_you_total'),
    );
  }

  static String get _visibleStreamColumns => '''
    v.id,
    v.account_id,
    v.category,
    v.kind,
    v.priority,
    v.title,
    v.body,
    v.action_url,
    v.created_at,
    v.collapsed_count,
    v.beacon_id,
    v.coordination_item_id,
    v.actor_user_id,
    v.seen_at,
    v.source_event_key,
    v.destination_kind,
    v.target_entity_id,
    v.presentation_key,
    v.presentation_payload,
    v.in_app_preference_class,
    v.suppression_class,
    v.access_policy,
    v.requires_action,
    v.attention_thread_key,
    v.settlement_kind,
    v.settled_at,
    v.settled_by_user_id,
    v.settled_by_occurrence_id,
    v.tombstone_copy,
    v.cleared_at,
    v.clear_reason,
    v.surface,
    (
      ${AttentionDismissibleSql.activeAttention('v')}
      AND ${AttentionDismissibleSql.primaryPlacement('v')}
    ) AS is_active_attention''';

  /// Eligible inbox representatives + child Activity stats shared by the stream.
  ///
  /// Beacon-scoped Activity receipts coalesce onto a pinned For-you card, a
  /// stream forward row, or a synthetic `requestActivity` row — never as
  /// standalone feed tiles.
  /// The pinned zone is shared with the sweep — see [_visibleWithSurfaceCte].
  ///
  /// U10b — grouping eligibility is *active attention*, not "any receipt".
  /// `event_total` and `event_unseen_count` count only rows that still ask for
  /// something, so a `requestActivity` group whose children have all been
  /// cleared retires (gated below on `event_total > 0`) instead of lingering
  /// as an empty card.
  ///
  /// U10c — two keys, not one. `min_created_at` is the **position** key of a
  /// synthetic group (when it entered the surface); `max_created_at` is its
  /// **latest-event** key (what the preview is about). Both stay over *every*
  /// child rather than over the active ones: they are ordering inputs, and
  /// narrowing them would make clearing or receiving an optional event
  /// silently reshuffle the zone — the defect this unit inherited.
  static String get _activityGroupingCtes =>
      '''
${AttentionDismissibleSql.eligiblePinned},
request_entry AS (
  SELECT state.beacon_id, state.first_entry_at
  FROM public.attention_request_state state
  WHERE state.account_id = \$1
),
eligible_forward AS (
  SELECT
    ii.beacon_id,
    ii.status,
    ii.forward_count,
    ii.latest_forward_at,
    COALESCE(re.first_entry_at, ii.latest_forward_at) AS entry_at,
    ii.tombstone_dismissed_at,
    b.title AS beacon_title,
    public.beacon_can_read_content(ii.beacon_id, \$1) AS can_read_content,
    public.beacon_can_read_tombstone(ii.beacon_id, \$1) AS can_read_tombstone
  FROM public.inbox_item ii
  JOIN public.beacon b ON b.id = ii.beacon_id
  LEFT JOIN request_entry re ON re.beacon_id = ii.beacon_id
  WHERE ii.user_id = \$1
    AND ii.tombstone_dismissed_at IS NULL
    AND (
      ii.status <> 0
      OR ii.beacon_id IN (SELECT scope.beacon_id FROM scope)
    )
    AND (
      public.beacon_can_read_content(ii.beacon_id, \$1)
      OR (
        ii.status IN (3, 4)
        AND public.beacon_can_read_tombstone(ii.beacon_id, \$1)
      )
    )
),
-- U15R-a / R1 — *representative* now means "an attention object that owns
-- this Request's children", and only the pinned zone is one. An outcome row
-- is a dated memory of the viewer's own act (contract section 7, owner
-- decision B): it carries no dot and no sub-cards, so it cannot be the thing
-- a live optional event hangs from. Before this, being answered — or having
-- the answer's trace dismissed — silently vetoed the Request's live
-- attention while that attention kept feeding the tab total: a lit tab over
-- a surface with nothing on it.
eligible_representative AS (
  SELECT beacon_id FROM eligible_pinned
),
activity_child_receipts AS (
  SELECT v.*
  FROM visible v
  WHERE v.surface = 'activity'
    AND v.beacon_id IS NOT NULL
    AND v.presentation_key IS DISTINCT FROM 'relay_received'
    -- U11/D16, the load-bearing one. Everything a grouped For You row says
    -- about itself comes from here: `event_total` (the count),
    -- `event_unseen_count` (the dot), `MIN(created_at)` (its position) and
    -- `MAX(created_at)` (its freshness). A hierarchy notice propagated from a
    -- child is in the parent's log and in none of those — and because
    -- `event_total` is also the gate on the synthetic `requestActivity` row, a
    -- Request whose only receipt is such a notice grows no card at all.
    AND ${AttentionDismissibleSql.primaryPlacement('v')}
),
beacon_activity_stats AS (
  SELECT
    beacon_id,
    MAX(created_at) AS max_created_at,
    MIN(created_at) AS min_created_at,
    COUNT(*) FILTER (
      WHERE ${AttentionDismissibleSql.activeAttention('child')}
    )::int AS event_total,
    COUNT(*) FILTER (
      WHERE ${AttentionDismissibleSql.activeOptional('child')}
    )::int AS event_unseen_count
  FROM activity_child_receipts child
  GROUP BY beacon_id
)''';

  static String get _activityPageStreamCte => '''
$_activityGroupingCtes,
page_stream AS (
  SELECT
    $_visibleStreamColumns,
    'receipt'::text AS item_kind,
    NULL::text AS forward_outcome,
    NULL::int AS forward_count,
    NULL::int AS digest_count,
    NULL::int AS event_total,
    NULL::int AS event_unseen_count
  FROM visible v
  WHERE v.surface = 'activity'
    AND v.beacon_id IS NULL

  UNION ALL

  SELECT
    ('inbox:' || ef.beacon_id) AS id,
    \$1::text AS account_id,
    'coordination'::text AS category,
    'newRelay'::text AS kind,
    'normal'::text AS priority,
    CASE
      WHEN ef.can_read_content THEN COALESCE(ef.beacon_title, '')
      ELSE ''::text
    END AS title,
    ''::text AS body,
    ('/#/view?id=' || ef.beacon_id) AS action_url,
    -- U10c: the *position* key. A forward row sits where the Request
    -- entered, not where its newest child event is (see the contract's
    -- section 6). The latest-event key stays available via the stats.
    ef.entry_at AS created_at,
    0 AS collapsed_count,
    ef.beacon_id,
    NULL::text AS coordination_item_id,
    NULL::text AS actor_user_id,
    -- U15R-a / R1: never null. An outcome row has no unread axis of its own
    -- (owner decision B, contract section 7 — "no dot"); its Request's live
    -- attention lights the `requestActivity` row instead.
    ef.latest_forward_at AS seen_at,
    NULL::text AS source_event_key,
    'beacon'::text AS destination_kind,
    ef.beacon_id AS target_entity_id,
    'relay_received'::text AS presentation_key,
    '{}'::jsonb AS presentation_payload,
    NULL::text AS in_app_preference_class,
    'standard'::text AS suppression_class,
    'beacon_content'::text AS access_policy,
    false AS requires_action,
    NULL::text AS attention_thread_key,
    NULL::text AS settlement_kind,
    NULL::timestamptz AS settled_at,
    NULL::text AS settled_by_user_id,
    NULL::text AS settled_by_occurrence_id,
    (
      NOT ef.can_read_content
      AND NOT (
        ef.status IN (3, 4)
        AND ef.can_read_tombstone
      )
    ) AS tombstone_copy,
    NULL::timestamptz AS cleared_at,
    NULL::text AS clear_reason,
    'activity'::text AS surface,
    -- U15R-a / R1: an outcome row is dismissible, but it is not a second
    -- attention object and it never carries the dot — the children it used
    -- to borrow one from now own their own row.
    false AS is_active_attention,
    'forward'::text AS item_kind,
    CASE
      WHEN ef.beacon_id IN (SELECT scope.beacon_id FROM scope) THEN 'helping'
      WHEN ef.status = 1 THEN 'watching'
      WHEN ef.status = 2 THEN 'notInterested'
      WHEN ef.status = 3 THEN 'closedBeforeResponse'
      WHEN ef.status = 4 THEN 'deletedBeforeResponse'
      ELSE NULL::text
    END AS forward_outcome,
    ef.forward_count AS forward_count,
    NULL::int AS digest_count,
    -- U15R-a / R1: "no sub-cards" for every outcome, not only the helping
    -- one. The counts stay reachable — on the Request's own row.
    0 AS event_total,
    0 AS event_unseen_count
  FROM eligible_forward ef

  UNION ALL

  SELECT
    ('activity-beacon:' || stats.beacon_id) AS id,
    \$1::text AS account_id,
    'coordination'::text AS category,
    'roomActivityLowPriority'::text AS kind,
    'normal'::text AS priority,
    CASE
      WHEN public.beacon_can_read_content(stats.beacon_id, \$1)
      THEN COALESCE(b.title, '')
      ELSE ''::text
    END AS title,
    ''::text AS body,
    ('/#/view?id=' || stats.beacon_id) AS action_url,
    -- U10c: a synthetic group has no inbox row and therefore no
    -- `first_entry_at`; its entry is the first child that put it on the
    -- surface, which is immutable and does not move when a second arrives.
    stats.min_created_at AS created_at,
    0 AS collapsed_count,
    stats.beacon_id,
    NULL::text AS coordination_item_id,
    NULL::text AS actor_user_id,
    CASE
      WHEN stats.event_unseen_count > 0 THEN NULL::timestamptz
      ELSE stats.max_created_at
    END AS seen_at,
    NULL::text AS source_event_key,
    'beacon'::text AS destination_kind,
    stats.beacon_id AS target_entity_id,
    'request_status_changed'::text AS presentation_key,
    '{}'::jsonb AS presentation_payload,
    NULL::text AS in_app_preference_class,
    'standard'::text AS suppression_class,
    'beacon_content'::text AS access_policy,
    false AS requires_action,
    NULL::text AS attention_thread_key,
    NULL::text AS settlement_kind,
    NULL::timestamptz AS settled_at,
    NULL::text AS settled_by_user_id,
    NULL::text AS settled_by_occurrence_id,
    NOT public.beacon_can_read_content(stats.beacon_id, \$1) AS tombstone_copy,
    NULL::timestamptz AS cleared_at,
    NULL::text AS clear_reason,
    'activity'::text AS surface,
    (stats.event_unseen_count > 0) AS is_active_attention,
    'requestActivity'::text AS item_kind,
    NULL::text AS forward_outcome,
    NULL::int AS forward_count,
    NULL::int AS digest_count,
    stats.event_total,
    stats.event_unseen_count
  FROM beacon_activity_stats stats
  JOIN public.beacon b ON b.id = stats.beacon_id
  WHERE stats.event_total > 0
    AND stats.beacon_id NOT IN (SELECT beacon_id FROM eligible_representative)
    -- U15R-a / R1: deliberately *not* gated on `tombstone_dismissed_at`.
    -- Putting the memory away is not a decision about what the Request does
    -- next. The tombstone itself stays gone — `eligible_forward` still
    -- excludes it — so nothing is resurrected here; only live attention that
    -- the tab is already counting becomes reachable again.
    AND stats.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)

  UNION ALL

  SELECT
    'watching-digest'::text AS id,
    \$1::text AS account_id,
    'ambient'::text AS category,
    'roomActivityLowPriority'::text AS kind,
    'low'::text AS priority,
    ''::text AS title,
    ''::text AS body,
    ''::text AS action_url,
    digest.max_created_at AS created_at,
    0 AS collapsed_count,
    NULL::text AS beacon_id,
    NULL::text AS coordination_item_id,
    NULL::text AS actor_user_id,
    NULL::timestamptz AS seen_at,
    NULL::text AS source_event_key,
    NULL::text AS destination_kind,
    NULL::text AS target_entity_id,
    'request_status_changed'::text AS presentation_key,
    '{}'::jsonb AS presentation_payload,
    NULL::text AS in_app_preference_class,
    'standard'::text AS suppression_class,
    'legacy'::text AS access_policy,
    false AS requires_action,
    NULL::text AS attention_thread_key,
    NULL::text AS settlement_kind,
    NULL::timestamptz AS settled_at,
    NULL::text AS settled_by_user_id,
    NULL::text AS settled_by_occurrence_id,
    false AS tombstone_copy,
    NULL::timestamptz AS cleared_at,
    NULL::text AS clear_reason,
    'activity'::text AS surface,
    true AS is_active_attention,
    'watchingDigest'::text AS item_kind,
    NULL::text AS forward_outcome,
    NULL::int AS forward_count,
    digest.beacon_count AS digest_count,
    NULL::int AS event_total,
    NULL::int AS event_unseen_count
  FROM (
    SELECT
      MAX(v.created_at) AS max_created_at,
      COUNT(DISTINCT ii.beacon_id)::int AS beacon_count
    FROM public.inbox_item ii
    INNER JOIN visible v
      ON v.beacon_id = ii.beacon_id
     AND ${AttentionDismissibleSql.activeOptional('v')}
     AND ${AttentionDismissibleSql.primaryPlacement('v')}
     AND v.created_at > ii.latest_forward_at
    WHERE ii.user_id = \$1
      AND ii.status = 1
      AND ii.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
  ) digest
  WHERE digest.beacon_count > 0
)''';

  @override
  Future<AttentionFeed> attentionFeed({
    required String accountId,
    required AttentionFeedView view,
    AttentionCursor? cursor,
    String? search,
    AttentionSurface? surface,
    int limit = 50,
  }) async {
    final boundedLimit = limit.clamp(1, 100);
    final variables = <Variable>[
      Variable<String>(accountId),
      Variable<String>(view.name),
      Variable<String>(search),
      Variable<String>(surface?.name),
    ];
    final cursorClause = StringBuffer();
    final streamAlias = surface == AttentionSurface.activity ? 'stream' : 'visible';
    if (cursor != null) {
      variables
        ..add(Variable<String>(cursor.createdAt.toUtc().toIso8601String()))
        ..add(Variable<String>(cursor.id));
      cursorClause.write(
        '''
AND (
  $streamAlias.created_at < \$5::timestamptz
  OR ($streamAlias.created_at = \$5::timestamptz AND $streamAlias.id < \$6)
)''',
      );
    }
    variables.add(Variable<int>(boundedLimit + 1));
    final limitParameter = '\$${variables.length}';

    final pageCte = surface == AttentionSurface.activity
        ? '''
$_activityPageStreamCte,
page AS (
  SELECT stream.*
  FROM page_stream stream
  WHERE (
    \$2 = 'all'
    OR (\$2 = 'unread' AND stream.is_active_attention)
    OR (\$2 = 'needsYou' AND ${AttentionDismissibleSql.liveObligation('stream')})
  )
  AND (
    \$3::text IS NULL
    OR to_tsvector(
      'simple',
      coalesce(stream.presentation_payload ->> 'eventType', '') || ' ' ||
      coalesce(stream.presentation_payload ->> 'beaconId', '') || ' ' ||
      coalesce(stream.presentation_payload ->> 'coordinationItemId', '') || ' ' ||
      coalesce(stream.presentation_payload ->> 'targetEntityId', '') || ' ' ||
      coalesce(stream.presentation_payload ->> 'messageId', '')
    ) @@ websearch_to_tsquery('simple', \$3)
  )
  $cursorClause
  ORDER BY stream.created_at DESC, stream.id DESC
  LIMIT $limitParameter
)'''
        : '''
page AS (
  SELECT visible.*
  FROM visible
  WHERE (
    \$2 = 'all'
    OR (\$2 = 'unread' AND ${AttentionDismissibleSql.activeAttention('visible')})
    OR (\$2 = 'needsYou' AND ${AttentionDismissibleSql.liveObligation('visible')})
  )
  AND (
    \$3::text IS NULL
    OR to_tsvector(
      'simple',
      coalesce(visible.presentation_payload ->> 'eventType', '') || ' ' ||
      coalesce(visible.presentation_payload ->> 'beaconId', '') || ' ' ||
      coalesce(visible.presentation_payload ->> 'coordinationItemId', '') || ' ' ||
      coalesce(visible.presentation_payload ->> 'targetEntityId', '') || ' ' ||
      coalesce(visible.presentation_payload ->> 'messageId', '')
    ) @@ websearch_to_tsquery('simple', \$3)
  )
  AND (\$4::text IS NULL OR visible.surface = \$4)
    $cursorClause
  ORDER BY visible.created_at DESC, visible.id DESC
  LIMIT $limitParameter
)''';

    final rows = await _database.customSelect(
      '''
WITH $_visibleWithSurfaceCte,
summary AS (
  SELECT COUNT(*) FILTER (
    WHERE ${AttentionDismissibleSql.activeAttention('v')}
      AND (\$4::text IS NULL OR v.surface = \$4)
  )::int AS unread_total,
  COUNT(*) FILTER (
    WHERE ${AttentionDismissibleSql.liveObligation('v')}
  )::int AS needs_you_total
  FROM visible v
),
$pageCte
SELECT summary.unread_total, summary.needs_you_total, page.*
FROM summary
LEFT JOIN LATERAL (SELECT * FROM page) page ON true
ORDER BY page.created_at DESC NULLS LAST, page.id DESC NULLS LAST
''',
      variables: variables,
    ).get();

    final unreadTotal = rows.isEmpty ? 0 : rows.first.read<int>('unread_total');
    final needsYouTotal = rows.isEmpty
        ? 0
        : rows.first.read<int>('needs_you_total');
    var items = <AttentionReceipt>[
      for (final row in rows)
        if (row.data['id'] != null) _mapRow(row),
    ];
    final hasMore = items.length > boundedLimit;
    if (hasMore) {
      items = items.sublist(0, boundedLimit);
    }
    if (surface == AttentionSurface.activity) {
      items = await _attachActivityEventPreviews(
        accountId: accountId,
        items: items,
      );
      items = await _attachGroupedProvenance(
        accountId: accountId,
        items: items,
      );
    }
    final nextCursor = hasMore && items.isNotEmpty
        ? AttentionCursor(
            createdAt: items.last.createdAt,
            id: items.last.id,
          )
        : null;

    return AttentionFeed(
      summary: AttentionSummary(
        unreadTotal: unreadTotal,
        needsYouTotal: needsYouTotal,
      ),
      page: AttentionPage(items: items, nextCursor: nextCursor),
    );
  }

  AttentionReceipt _mapRow(QueryRow row) {
    final tombstoneCopy = row.read<bool>('tombstone_copy');
    final destinationName = row.readNullable<String>('destination_kind');
    final preferenceName = row.readNullable<String>(
      'in_app_preference_class',
    );
    return AttentionReceipt(
      id: row.read<String>('id'),
      accountId: row.read<String>('account_id'),
      category:
          notificationCategoryFromName(row.read<String>('category')) ??
          NotificationCategory.coordination,
      kind: _kindFromName(row.read<String>('kind')),
      priority: _priorityFromName(row.read<String>('priority')),
      title: tombstoneCopy
          ? kBeaconUnavailableNotificationTitle
          : row.read<String>('title'),
      body: tombstoneCopy
          ? kBeaconUnavailableNotificationBody
          : row.read<String>('body'),
      actionUrl: row.read<String>('action_url'),
      createdAt: _readTimestamp(row, 'created_at')!,
      collapsedCount: row.read<int>('collapsed_count'),
      beaconId: row.readNullable<String>('beacon_id'),
      coordinationItemId: row.readNullable<String>('coordination_item_id'),
      actorUserId: row.readNullable<String>('actor_user_id'),
      seenAt: _readTimestamp(row, 'seen_at'),
      sourceEventKey: row.readNullable<String>('source_event_key'),
      destinationKind: destinationName == null
          ? null
          : _destinationFromName(destinationName),
      targetEntityId: row.readNullable<String>('target_entity_id'),
      presentationKey: row.readNullable<String>('presentation_key'),
      presentationPayload: _readJsonObject(row, 'presentation_payload'),
      inAppPreferenceClass: preferenceName == null
          ? null
          : _preferenceFromName(preferenceName),
      suppressionClass: AttentionSuppressionClass.values.firstWhere(
        (value) => value.name == row.read<String>('suppression_class'),
        orElse: () => AttentionSuppressionClass.standard,
      ),
      accessPolicy: attentionAccessPolicyFromWireName(
        row.read<String>('access_policy'),
      ),
      requiresAction: row.read<bool>('requires_action'),
      attentionThreadKey: row.readNullable<String>('attention_thread_key'),
      settlementKind: row.readNullable<String>('settlement_kind') == null
          ? null
          : attentionSettlementKindFromWireName(
              row.read<String>('settlement_kind'),
            ),
      settledAt: _readTimestamp(row, 'settled_at'),
      settledByUserId: row.readNullable<String>('settled_by_user_id'),
      settledByOccurrenceId: row.readNullable<String>(
        'settled_by_occurrence_id',
      ),
      clearedAt: _readTimestamp(row, 'cleared_at'),
      clearReason: row.data.containsKey('clear_reason')
          ? row.readNullable<String>('clear_reason')
          : null,
      surface: attentionSurfaceFromWireName(row.read<String>('surface')),
      itemKind: row.data['item_kind'] == null
          ? AttentionItemKind.receipt
          : attentionItemKindFromWireName(row.read<String>('item_kind')),
      forwardOutcome: row.readNullable<String>('forward_outcome'),
      forwardCount: row.readNullable<int>('forward_count'),
      digestCount: row.readNullable<int>('digest_count'),
      eventTotal: row.data['event_total'] == null
          ? null
          : row.readNullable<int>('event_total'),
      eventUnseenCount: row.data['event_unseen_count'] == null
          ? null
          : row.readNullable<int>('event_unseen_count'),
    );
  }

  Future<List<AttentionReceipt>> _attachActivityEventPreviews({
    required String accountId,
    required List<AttentionReceipt> items,
  }) async {
    final beaconIds = <String>{
      for (final item in items)
        // U15R-a / R1: only the Request's own row. An outcome row carries no
        // sub-cards at all (owner decision B), helping or not, so it is not a
        // preview destination — previously every non-helping outcome got one.
        if (item.beaconId != null &&
            item.itemKind == AttentionItemKind.requestActivity &&
            (item.eventTotal ?? 0) > 0)
          item.beaconId!,
    };
    if (beaconIds.isEmpty) {
      return items;
    }
    final byBeacon = await _loadActivityChildReceipts(
      accountId: accountId,
      beaconIds: beaconIds,
      limitPerBeacon: kActivityEventPreviewCap,
    );
    return [
      for (final item in items)
        // U15R-a / R1: keyed on the *item*, not merely on its Request — an
        // outcome row shares a `beaconId` with the Request's own row and must
        // not inherit its sub-cards.
        if (item.itemKind == AttentionItemKind.requestActivity &&
            item.beaconId != null &&
            byBeacon.containsKey(item.beaconId))
          item.copyWith(eventsPreview: byBeacon[item.beaconId]!)
        else
          item,
    ];
  }

  /// U10d — §0.1a provenance for the grouped `beacon:` rows on this page.
  ///
  /// Attached after paging rather than projected inside `page_stream`, for the
  /// same reason [_attachActivityEventPreviews] is: the provenance body walks
  /// the forward edges and the MR scores per Request, and doing that for every
  /// eligible Request before the `LIMIT` would pay for rows nobody asked for.
  ///
  /// **Authorization.** Everything here hangs off one call to the existing
  /// content wall, `beacon_can_read_content` — the same predicate the
  /// projection already uses to decide [AttentionReceipt.title] and the
  /// tombstone copy. A Request the viewer cannot read yields no senders, no
  /// count, no header identity and no forward affordance. Blocked forwarders
  /// are dropped a level deeper, inside `attention_provenance_data`, so they
  /// leave the count as well as the list — a number that reveals a hidden
  /// person is still a leak.
  Future<List<AttentionReceipt>> _attachGroupedProvenance({
    required String accountId,
    required List<AttentionReceipt> items,
  }) async {
    final beaconIds = <String>{
      for (final item in items)
        if (item.beaconId != null &&
            (item.itemKind == AttentionItemKind.forward ||
                item.itemKind == AttentionItemKind.requestActivity))
          item.beaconId!,
    };
    if (beaconIds.isEmpty) {
      return items;
    }
    final ids = beaconIds.toList(growable: false);
    final placeholders = List.generate(
      ids.length,
      (index) => '\$${index + 2}',
    ).join(',');
    final rows = await _database.customSelect(
      '''
WITH readable AS (
  SELECT
    b.id AS beacon_id,
    b.user_id AS author_id,
    b.title AS beacon_title,
    b.end_at AS beacon_end_at,
    b.status AS beacon_status,
    ii.context AS inbox_context,
    public.beacon_can_read_content(b.id, \$1) AS can_read_content
  FROM public.beacon b
  LEFT JOIN public.inbox_item ii
    ON ii.beacon_id = b.id AND ii.user_id = \$1
  WHERE b.id IN ($placeholders)
)
SELECT
  readable.beacon_id,
  CASE
    WHEN readable.can_read_content
    THEN public.attention_provenance_data(
      readable.beacon_id,
      \$1,
      \$1,
      readable.inbox_context,
      true
    )::text
  END AS provenance_json,
  CASE WHEN readable.can_read_content THEN readable.author_id END
    AS beacon_author_id,
  CASE
    WHEN readable.can_read_content
    THEN coalesce(nullif(trim(author.display_name), ''), '')
  END AS beacon_author_name,
  CASE WHEN readable.can_read_content THEN author.image_id::text END
    AS beacon_author_image_id,
  CASE
    WHEN readable.can_read_content
    THEN coalesce(
      b.cover_image_id,
      (
        SELECT bi.image_id
        FROM public.beacon_image bi
        WHERE bi.beacon_id = readable.beacon_id
        ORDER BY bi.position ASC, bi.image_id ASC
        LIMIT 1
      )
    )::text
  END AS beacon_image_id,
  CASE WHEN readable.can_read_content THEN readable.beacon_end_at END
    AS beacon_end_at,
  (
    readable.can_read_content
    AND readable.beacon_status IN ($_openFamilyStatusList)
  ) AS allows_forward
FROM readable
JOIN public.beacon b ON b.id = readable.beacon_id
JOIN public."user" author ON author.id = readable.author_id
''',
      variables: [
        Variable<String>(accountId),
        ...ids.map(Variable<String>.new),
      ],
    ).get();

    final byBeacon = {
      for (final row in rows)
        row.read<String>('beacon_id'): (
          provenanceJson: row.readNullable<String>('provenance_json'),
          beaconAuthorId: row.readNullable<String>('beacon_author_id'),
          beaconAuthorName: row.readNullable<String>('beacon_author_name'),
          beaconAuthorImageId: row.readNullable<String>(
            'beacon_author_image_id',
          ),
          beaconImageId: row.readNullable<String>('beacon_image_id'),
          beaconEndAt: _readTimestamp(row, 'beacon_end_at'),
          allowsForward: row.read<bool>('allows_forward'),
        ),
    };

    return [
      for (final item in items)
        if (byBeacon[item.beaconId] case final provenance?
            when item.itemKind == AttentionItemKind.forward ||
                item.itemKind == AttentionItemKind.requestActivity)
          item.copyWith(
            provenanceJson: provenance.provenanceJson,
            beaconAuthorId: provenance.beaconAuthorId,
            beaconAuthorName: provenance.beaconAuthorName,
            beaconAuthorImageId: provenance.beaconAuthorImageId,
            beaconImageId: provenance.beaconImageId,
            beaconEndAt: provenance.beaconEndAt,
            allowsForward: provenance.allowsForward,
          )
        else
          item,
    ];
  }

  /// `BeaconStatus.allowsForward` as SQL — composed from the enum, so the
  /// action row cannot drift from the gate `forward_case.dart` enforces.
  static final String _openFamilyStatusList =
      (BeaconStatus.openFamilyValues.toList()..sort()).join(', ');

  Future<Map<String, List<AttentionReceipt>>> _loadActivityChildReceipts({
    required String accountId,
    required Set<String> beaconIds,
    required int limitPerBeacon,
    AttentionCursor? cursor,
  }) async {
    if (beaconIds.isEmpty) {
      return const {};
    }
    final ids = beaconIds.toList(growable: false);
    final placeholders = List.generate(
      ids.length,
      (index) => '\$${index + 2}',
    ).join(',');
    final variables = <Variable>[
      Variable<String>(accountId),
      ...ids.map(Variable<String>.new),
    ];
    final cursorClause = StringBuffer();
    if (cursor != null && beaconIds.length == 1) {
      variables
        ..add(Variable<String>(cursor.createdAt.toUtc().toIso8601String()))
        ..add(Variable<String>(cursor.id));
      final createdAtParam = '\$${variables.length - 1}';
      final idParam = '\$${variables.length}';
      cursorClause.write(
        '''
AND (
  v.created_at < $createdAtParam::timestamptz
  OR (v.created_at = $createdAtParam::timestamptz AND v.id < $idParam)
)''',
      );
    }
    variables.add(Variable<int>(limitPerBeacon));
    final limitParam = '\$${variables.length}';
    final rows = await _database
        .customSelect(
          '''
WITH $_visibleWithSurfaceCte,
ranked AS (
  SELECT
    $_visibleStreamColumns,
    'receipt'::text AS item_kind,
    NULL::text AS forward_outcome,
    NULL::int AS forward_count,
    NULL::int AS digest_count,
    NULL::int AS event_total,
    NULL::int AS event_unseen_count,
    ROW_NUMBER() OVER (
      PARTITION BY v.beacon_id
      ORDER BY v.created_at DESC, v.id DESC
    ) AS rn
  FROM visible v
  WHERE v.surface = 'activity'
    AND v.beacon_id IN ($placeholders)
    AND v.presentation_key IS DISTINCT FROM 'relay_received'
    AND ${AttentionDismissibleSql.activeAttention('v')}
    -- The preview is the expansion of `event_total`, so it is filtered by the
    -- same rule that produced that number. The Request's own log — History and
    -- the Request timeline — is a different query and keeps every notice.
    AND ${AttentionDismissibleSql.primaryPlacement('v')}
    $cursorClause
)
SELECT *
FROM ranked
WHERE rn <= $limitParam
ORDER BY beacon_id, created_at DESC, id DESC
''',
          variables: variables,
        )
        .get();

    final byBeacon = <String, List<AttentionReceipt>>{};
    for (final row in rows) {
      final receipt = _mapRow(row);
      final beaconId = receipt.beaconId;
      if (beaconId == null) {
        continue;
      }
      byBeacon.putIfAbsent(beaconId, () => []).add(receipt);
    }
    return byBeacon;
  }

  @override
  Future<ActivityOfferPage> activityOffers({
    required String accountId,
    AttentionCursor? cursor,
    int limit = 20,
  }) async {
    final boundedLimit = limit.clamp(1, 100);
    final variables = <Variable>[Variable<String>(accountId)];
    final cursorClause = StringBuffer();
    if (cursor != null) {
      variables
        ..add(Variable<String>(cursor.createdAt.toUtc().toIso8601String()))
        ..add(Variable<String>(cursor.id));
      cursorClause.write(
        '''
AND (
  ranked.list_position_at < \$2::timestamptz
  OR (
    ranked.list_position_at = \$2::timestamptz
    AND ranked.beacon_id < \$3
  )
)''',
      );
    }
    variables.add(Variable<int>(boundedLimit + 1));
    final limitParam = '\$${variables.length}';

    final rows = await _database
        .customSelect(
          '''
WITH $_visibleWithSurfaceCte,
$_activityGroupingCtes,
ranked AS (
  SELECT
    ep.beacon_id,
    ii.latest_forward_at,
    -- U10c: the pinned zone is ordered by the *position* key and never by
    -- the latest-event key. `effective_activity_at` survives as the
    -- latest-event key because a card still has to say how fresh its noise
    -- is; it is no longer what decides where the card sits.
    COALESCE(re.first_entry_at, ii.latest_forward_at) AS list_position_at,
    GREATEST(
      ii.latest_forward_at,
      COALESCE(stats.max_created_at, ii.latest_forward_at)
    ) AS effective_activity_at,
    COALESCE(stats.event_total, 0) AS event_total,
    COALESCE(stats.event_unseen_count, 0) AS event_unseen_count,
    EXISTS (
      SELECT 1
      FROM visible act
      WHERE act.beacon_id = ep.beacon_id
        AND act.surface = 'activity'
        AND ${AttentionDismissibleSql.activeOptional('act')}
        AND ${AttentionDismissibleSql.primaryPlacement('act')}
    ) AS unseen
  FROM eligible_pinned ep
  JOIN public.inbox_item ii
    ON ii.user_id = \$1
   AND ii.beacon_id = ep.beacon_id
  LEFT JOIN request_entry re ON re.beacon_id = ep.beacon_id
  LEFT JOIN beacon_activity_stats stats ON stats.beacon_id = ep.beacon_id
)
SELECT *
FROM ranked
WHERE true
  $cursorClause
ORDER BY ranked.list_position_at DESC, ranked.beacon_id DESC
LIMIT $limitParam
''',
          variables: variables,
        )
        .get();

    final countRow = await _database
        .customSelect(
          '''
WITH $_visibleWithSurfaceCte,
$_activityGroupingCtes
SELECT COUNT(*)::int AS total_count
FROM eligible_pinned
''',
          variables: [Variable<String>(accountId)],
        )
        .getSingle();
    final totalCount = countRow.read<int>('total_count');

    var sortRows = [
      for (final row in rows)
        ActivityOfferSortRow(
          beaconId: row.read<String>('beacon_id'),
          listPositionAt: _readTimestamp(row, 'list_position_at')!,
          effectiveActivityAt: _readTimestamp(row, 'effective_activity_at')!,
          latestForwardAt: _readTimestamp(row, 'latest_forward_at')!,
          unseen: row.read<bool>('unseen'),
          eventTotal: row.read<int>('event_total'),
          eventUnseenCount: row.read<int>('event_unseen_count'),
        ),
    ];
    final hasMore = sortRows.length > boundedLimit;
    if (hasMore) {
      sortRows = sortRows.sublist(0, boundedLimit);
    }

    final previews = await _loadActivityChildReceipts(
      accountId: accountId,
      beaconIds: {
        for (final row in sortRows)
          if (row.eventTotal > 0) row.beaconId,
      },
      limitPerBeacon: kActivityEventPreviewCap,
    );
    final items = [
      for (final row in sortRows)
        row.copyWith(eventsPreview: previews[row.beaconId] ?? const []),
    ];
    final nextCursor = hasMore
        ? AttentionCursor(
            createdAt: items.last.listPositionAt,
            id: items.last.beaconId,
          )
        : null;
    return ActivityOfferPage(
      items: items,
      totalCount: totalCount,
      nextCursor: nextCursor,
    );
  }

  @override
  Future<AttentionPage> attentionRequestHistory({
    required String accountId,
    required String beaconId,
    AttentionCursor? cursor,
    int limit = 50,
  }) async {
    final boundedLimit = limit.clamp(1, 100);
    final variables = <Variable>[
      Variable<String>(accountId),
      Variable<String>(beaconId),
    ];
    final cursorClause = StringBuffer();
    if (cursor != null) {
      variables
        ..add(Variable<String>(cursor.createdAt.toUtc().toIso8601String()))
        ..add(Variable<String>(cursor.id));
      final createdAtParam = '\$${variables.length - 1}';
      final idParam = '\$${variables.length}';
      cursorClause.write(
        '''
AND (
  v.created_at < $createdAtParam::timestamptz
  OR (v.created_at = $createdAtParam::timestamptz AND v.id < $idParam)
)''',
      );
    }
    variables.add(Variable<int>(boundedLimit + 1));
    final limitParam = '\$${variables.length}';

    final rows = await _database
        .customSelect(
          '''
WITH $_visibleWithSurfaceCte,
page AS (
  SELECT
$_visibleStreamColumns
  FROM visible v
  WHERE v.beacon_id = \$2
  $cursorClause
  ORDER BY v.created_at DESC, v.id DESC
  LIMIT $limitParam
)
SELECT * FROM page
''',
          variables: variables,
        )
        .get();

    var items = [for (final row in rows) _mapRow(row)];
    final hasMore = items.length > boundedLimit;
    if (hasMore) {
      items = items.sublist(0, boundedLimit);
    }
    return AttentionPage(
      items: items,
      nextCursor: hasMore && items.isNotEmpty
          ? AttentionCursor(
              createdAt: items.last.createdAt,
              id: items.last.id,
            )
          : null,
    );
  }

  @override
  Future<ActivityBeaconAttention> activityAttention({
    required String accountId,
    required String beaconId,
    AttentionCursor? cursor,
    int limit = 20,
  }) async {
    final boundedLimit = limit.clamp(1, 100);
    final statsRows = await _database
        .customSelect(
          '''
WITH $_visibleWithSurfaceCte,
$_activityGroupingCtes
SELECT
  COALESCE(stats.event_total, 0) AS event_total,
  COALESCE(stats.event_unseen_count, 0) AS event_unseen_count,
  stats.max_created_at
FROM (SELECT 1) dummy
LEFT JOIN beacon_activity_stats stats ON stats.beacon_id = \$2
WHERE \$2 NOT IN (SELECT scope.beacon_id FROM scope)
''',
          variables: [
            Variable<String>(accountId),
            Variable<String>(beaconId),
          ],
        )
        .get();
    final stats = statsRows.isEmpty ? null : statsRows.first;
    final eventTotal = stats?.read<int>('event_total') ?? 0;
    final unseenCount = stats?.read<int>('event_unseen_count') ?? 0;
    final latestAt =
        stats == null ? null : _readTimestamp(stats, 'max_created_at');

    final byBeacon = await _loadActivityChildReceipts(
      accountId: accountId,
      beaconIds: {beaconId},
      limitPerBeacon: boundedLimit + 1,
      cursor: cursor,
    );
    var events = byBeacon[beaconId] ?? const <AttentionReceipt>[];
    final hasMore = events.length > boundedLimit;
    if (hasMore) {
      events = events.sublist(0, boundedLimit);
    }
    return ActivityBeaconAttention(
      beaconId: beaconId,
      eventTotal: eventTotal,
      unseenCount: unseenCount,
      latestAt: latestAt ??
          (events.isNotEmpty
              ? events.first.createdAt
              : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)),
      events: events,
      nextCursor: hasMore
          ? AttentionCursor(
              createdAt: events.last.createdAt,
              id: events.last.id,
            )
          : null,
    );
  }

  static DateTime? _readTimestamp(QueryRow row, String column) {
    final value = row.data[column];
    if (value == null) {
      return null;
    }
    if (value is DateTime) {
      return value;
    }
    if (value is PgDateTime) {
      return value.dateTime;
    }
    return DateTime.parse(value.toString());
  }

  static Map<String, Object?> _readJsonObject(QueryRow row, String column) {
    final value = row.data[column];
    if (value is Map) {
      return Map<String, Object?>.from(value);
    }
    return Map<String, Object?>.from(jsonDecode(value.toString()) as Map);
  }

  static NotificationKind _kindFromName(String name) =>
      NotificationKind.values.firstWhere(
        (kind) => kind.name == name,
        orElse: () => NotificationKind.coordinationChanged,
      );

  static NotificationPriority _priorityFromName(String name) =>
      NotificationPriority.values.firstWhere(
        (priority) => priority.name == name,
        orElse: () => NotificationPriority.normal,
      );

  static AttentionDestinationKind? _destinationFromName(String name) {
    for (final destination in AttentionDestinationKind.values) {
      if (destination.wireName == name) {
        return destination;
      }
    }
    return null;
  }

  static AttentionPreferenceClass? _preferenceFromName(String name) {
    for (final preference in AttentionPreferenceClass.values) {
      if (preference.wireName == name) {
        return preference;
      }
    }
    return null;
  }
}

@Singleton(as: AttentionAckPort)
class AttentionAckRepository implements AttentionAckPort {
  const AttentionAckRepository(this._database);

  final TenturaDb _database;

  @override
  Future<int> markSeen({
    required String accountId,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) {
      return 0;
    }
    final placeholders = List.generate(
      ids.length,
      (index) => '\$${index + 2}',
    ).join(', ');
    return _database.customUpdate(
      '''
UPDATE public.notification_outbox outbox
SET
  seen_at = COALESCE(outbox.seen_at, now())
WHERE outbox.account_id = \$1
  AND outbox.seen_at IS NULL
  AND outbox.id IN ($placeholders)
  AND outbox.id IN (
    SELECT receipt_id
    FROM public.visible_attention_receipts(\$1)
  )
''',
      variables: [
        Variable<String>(accountId),
        for (final id in ids) Variable<String>(id),
      ],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<int> markUnseen({
    required String accountId,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) {
      return 0;
    }
    final placeholders = List.generate(
      ids.length,
      (index) => '\$${index + 2}',
    ).join(', ');
    try {
      return await _database.customUpdate(
        '''
UPDATE public.notification_outbox outbox
SET
  seen_at = NULL
WHERE outbox.account_id = \$1
  AND outbox.seen_at IS NOT NULL
  AND outbox.id IN ($placeholders)
  AND outbox.id IN (
    SELECT receipt_id
    FROM public.visible_attention_receipts(\$1)
  )
  AND NOT EXISTS (
    SELECT 1
    FROM public.notification_outbox sibling
    WHERE sibling.dedup_key = outbox.dedup_key
      AND sibling.id <> outbox.id
      AND sibling.seen_at IS NULL
  )
''',
        variables: [
          Variable<String>(accountId),
          for (final id in ids) Variable<String>(id),
        ],
        updateKind: UpdateKind.update,
      );
    } on UniqueViolationException {
      return 0;
    }
  }

  @override
  Future<int> markAllSeen(String accountId, {AttentionSurface? surface}) =>
      _database.customUpdate(
        // U10a: this was a third copy of the visible/surface CTE — projecting
        // fewer columns, but selecting the same rows. It composes the shared
        // definition like every other consumer now.
        '''
WITH ${AttentionDismissibleSql.visibleWithSurface},
targets AS (
  SELECT id
  FROM visible
  WHERE seen_at IS NULL
    AND (\$2::text IS NULL OR surface = \$2)
)
UPDATE public.notification_outbox outbox
SET
  seen_at = COALESCE(outbox.seen_at, now())
FROM targets
WHERE outbox.account_id = \$1
  AND outbox.id = targets.id
''',
        variables: [
          Variable<String>(accountId),
          Variable<String>(surface?.name),
        ],
        updateKind: UpdateKind.update,
      );

  @override
  Future<int> markSeenForBeacon({
    required String accountId,
    required String beaconId,
  }) =>
      _database.customUpdate(
        '''
UPDATE public.notification_outbox outbox
SET
  seen_at = COALESCE(outbox.seen_at, now())
WHERE outbox.account_id = \$1
  AND outbox.seen_at IS NULL
  AND outbox.beacon_id = \$2
  AND outbox.id IN (
    SELECT receipt_id
    FROM public.visible_attention_receipts(\$1)
  )
''',
        variables: [
          Variable<String>(accountId),
          Variable<String>(beaconId),
        ],
        updateKind: UpdateKind.update,
      );

  @override
  Future<int> bridgeRoomWatermark({
    required String accountId,
    required String beaconId,
    required String? threadItemId,
    required DateTime lastSeenAt,
  }) async {
    final row = await _database
        .customSelect(
          r'''
SELECT public.bridge_attention_room_seen(
  $1,
  $2,
  $3,
  $4::timestamptz
) AS updated_count
''',
          variables: [
            Variable<String>(accountId),
            Variable<String>(beaconId),
            Variable<String>(threadItemId),
            Variable<String>(lastSeenAt.toUtc().toIso8601String()),
          ],
        )
        .getSingle();
    return row.read<int>('updated_count');
  }
}

@Singleton(as: AttentionSettlementPort)
class AttentionSettlementRepository implements AttentionSettlementPort {
  const AttentionSettlementRepository(this._database);

  final TenturaDb _database;

  static const _reviewOpenedEventType = 'reviewOpened';
  static const _helpOfferSubmittedEventType = 'helpOfferSubmitted';

  @override
  Future<String?> liveObligationEventType({
    required String accountId,
    required String receiptId,
  }) async {
    final row = await _database
        .customSelect(
          r'''
SELECT occ.event_type AS event_type
FROM public.notification_outbox AS outbox
JOIN public.attention_occurrence AS occ ON occ.id = outbox.occurrence_id
WHERE outbox.id = $2
  AND outbox.account_id = $1
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
''',
          variables: [
            Variable<String>(accountId),
            Variable<String>(receiptId),
          ],
        )
        .getSingleOrNull();
    return row?.read<String>('event_type');
  }

  /// Second layer behind [AttentionSettlementCase] for owner decision C
  /// (U07b2): the statement itself matches no obligation kind, so a caller
  /// that reaches the repository directly still cannot acknowledge one away.
  @override
  Future<int> settle({
    required String accountId,
    required String receiptId,
    required AttentionSettlementKind kind,
  }) => _database.customUpdate(
    r'''
UPDATE public.notification_outbox outbox
SET
  settlement_kind = $3,
  settled_at = now(),
  settled_by_user_id = $1,
  settled_by_occurrence_id = NULL
FROM public.attention_occurrence AS occ
WHERE outbox.occurrence_id = occ.id
  AND outbox.id = $2
  AND outbox.account_id = $1
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
  AND outbox.id IN (
    SELECT receipt_id
    FROM public.visible_attention_receipts($1)
  )
  AND ($3 <> 'dismissed' OR outbox.suppression_class <> 'mandatory')
  AND occ.event_type IS DISTINCT FROM $4
  AND occ.event_type IS DISTINCT FROM $5
''',
    variables: [
      Variable<String>(accountId),
      Variable<String>(receiptId),
      Variable<String>(kind.wireName),
      Variable<String>(_reviewOpenedEventType),
      Variable<String>(_helpOfferSubmittedEventType),
    ],
    updateKind: UpdateKind.update,
  );
}
