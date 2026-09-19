import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart' show PgDateTime;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/coordination/filter_beacon_notifications.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/attention_ack_port.dart';
import 'package:tentura_server/domain/port/attention_query_port.dart';
import 'package:tentura_server/domain/port/attention_settlement_port.dart';

import '../database/tentura_db.dart';

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
WHERE receipt.seen_at IS NULL
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
)
SELECT * FROM scoped_receipts
ORDER BY beacon_id, created_at DESC, id DESC
''',
          variables: [
            Variable<String>(accountId),
            ...ids.map(Variable<String>.new),
          ],
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

    final results = <MyWorkBeaconAttention>[];
    for (final entry in byBeacon.entries) {
      final receipts = entry.value;
      final unseenCount = receipts.where((receipt) => receipt.isUnread).length;
      final liveObligations = [
        for (final receipt in receipts)
          if (receipt.isLiveObligation) receipt,
      ];
      if (unseenCount == 0 && liveObligations.isEmpty) {
        continue;
      }
      AttentionReceipt? latestUnseen;
      for (final receipt in receipts) {
        if (receipt.isUnread && !receipt.isLiveObligation) {
          latestUnseen = receipt;
          break;
        }
      }
      results.add(
        MyWorkBeaconAttention(
          beaconId: entry.key,
          unseenCount: unseenCount,
          latestUnseen: latestUnseen,
          liveObligations: liveObligations,
        ),
      );
    }
    return results;
  }

  static const _visibleWithSurfaceCte = '''
visible_raw AS (
  SELECT outbox.*, authorized.tombstone_copy
  FROM public.visible_attention_receipts(\$1) authorized
  JOIN public.notification_outbox outbox
    ON outbox.id = authorized.receipt_id
),
scope AS (
  SELECT beacon_id FROM public.responsibility_scope_base_beacons(\$1)
  UNION
  SELECT DISTINCT visible_raw.beacon_id
  FROM visible_raw
  WHERE visible_raw.requires_action
    AND visible_raw.settlement_kind IS NULL
    AND visible_raw.beacon_id IS NOT NULL
),
visible AS (
  SELECT
    visible_raw.*,
    CASE
      WHEN visible_raw.beacon_id IS NOT NULL
       AND visible_raw.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN 'myWork'
      ELSE 'activity'
    END AS surface
  FROM visible_raw
)''';

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
      WHERE seen_at IS NULL AND surface = 'activity'
    )::int AS activity_unread_total,
    COUNT(*) FILTER (
      WHERE seen_at IS NULL AND surface = 'myWork'
    )::int AS my_work_unread_total,
    COUNT(*) FILTER (
      WHERE requires_action AND settlement_kind IS NULL
    )::int AS needs_you_total
  FROM visible
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

  static const _visibleStreamColumns = '''
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
    v.surface''';

  /// Eligible inbox representatives + child Activity stats shared by the stream.
  ///
  /// Beacon-scoped Activity receipts coalesce onto a pinned For-you card, a
  /// stream forward row, or a synthetic `requestActivity` row — never as
  /// standalone feed tiles.
  static const _activityGroupingCtes = '''
eligible_pinned AS (
  SELECT ii.beacon_id
  FROM public.inbox_item ii
  WHERE ii.user_id = \$1
    AND ii.tombstone_dismissed_at IS NULL
    AND ii.status = 0
    AND public.beacon_can_read_content(ii.beacon_id, \$1)
    AND ii.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
),
eligible_forward AS (
  SELECT
    ii.beacon_id,
    ii.status,
    ii.forward_count,
    ii.latest_forward_at,
    ii.tombstone_dismissed_at,
    b.title AS beacon_title,
    public.beacon_can_read_content(ii.beacon_id, \$1) AS can_read_content,
    public.beacon_can_read_tombstone(ii.beacon_id, \$1) AS can_read_tombstone
  FROM public.inbox_item ii
  JOIN public.beacon b ON b.id = ii.beacon_id
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
eligible_representative AS (
  SELECT beacon_id FROM eligible_pinned
  UNION
  SELECT beacon_id FROM eligible_forward
),
dismissed_tombstone AS (
  SELECT ii.beacon_id
  FROM public.inbox_item ii
  WHERE ii.user_id = \$1
    AND ii.tombstone_dismissed_at IS NOT NULL
),
activity_child_receipts AS (
  SELECT v.*
  FROM visible v
  WHERE v.surface = 'activity'
    AND v.beacon_id IS NOT NULL
    AND v.presentation_key IS DISTINCT FROM 'relay_received'
),
beacon_activity_stats AS (
  SELECT
    beacon_id,
    MAX(created_at) AS max_created_at,
    COUNT(*)::int AS event_total,
    COUNT(*) FILTER (WHERE seen_at IS NULL)::int AS event_unseen_count
  FROM activity_child_receipts
  GROUP BY beacon_id
)''';

  static const _activityPageStreamCte = '''
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
    GREATEST(
      ef.latest_forward_at,
      COALESCE(stats.max_created_at, ef.latest_forward_at)
    ) AS created_at,
    0 AS collapsed_count,
    ef.beacon_id,
    NULL::text AS coordination_item_id,
    NULL::text AS actor_user_id,
    CASE
      WHEN ef.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN GREATEST(
        ef.latest_forward_at,
        COALESCE(stats.max_created_at, ef.latest_forward_at)
      )
      WHEN EXISTS (
        SELECT 1
        FROM visible act
        WHERE act.beacon_id = ef.beacon_id
          AND act.surface = 'activity'
          AND act.seen_at IS NULL
      )
      THEN NULL::timestamptz
      ELSE GREATEST(
        ef.latest_forward_at,
        COALESCE(stats.max_created_at, ef.latest_forward_at)
      )
    END AS seen_at,
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
    'activity'::text AS surface,
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
    CASE
      WHEN ef.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN 0
      ELSE COALESCE(stats.event_total, 0)
    END AS event_total,
    CASE
      WHEN ef.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN 0
      ELSE COALESCE(stats.event_unseen_count, 0)
    END AS event_unseen_count
  FROM eligible_forward ef
  LEFT JOIN beacon_activity_stats stats ON stats.beacon_id = ef.beacon_id

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
    stats.max_created_at AS created_at,
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
    'activity'::text AS surface,
    'requestActivity'::text AS item_kind,
    NULL::text AS forward_outcome,
    NULL::int AS forward_count,
    NULL::int AS digest_count,
    stats.event_total,
    stats.event_unseen_count
  FROM beacon_activity_stats stats
  JOIN public.beacon b ON b.id = stats.beacon_id
  WHERE stats.beacon_id NOT IN (SELECT beacon_id FROM eligible_representative)
    AND stats.beacon_id NOT IN (SELECT beacon_id FROM dismissed_tombstone)
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
    'activity'::text AS surface,
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
     AND v.seen_at IS NULL
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
    OR (\$2 = 'unread' AND stream.seen_at IS NULL)
    OR (\$2 = 'needsYou' AND stream.requires_action
        AND stream.settlement_kind IS NULL)
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
    OR (\$2 = 'unread' AND visible.seen_at IS NULL)
    OR (\$2 = 'needsYou' AND visible.requires_action
        AND visible.settlement_kind IS NULL)
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
    WHERE seen_at IS NULL
      AND (\$4::text IS NULL OR surface = \$4)
  )::int AS unread_total,
  COUNT(*) FILTER (
    WHERE requires_action AND settlement_kind IS NULL
  )::int AS needs_you_total
  FROM visible
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
        if (item.beaconId != null &&
            (item.itemKind == AttentionItemKind.forward ||
                item.itemKind == AttentionItemKind.requestActivity) &&
            item.forwardOutcome != 'helping' &&
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
        if (item.beaconId != null && byBeacon.containsKey(item.beaconId))
          item.copyWith(eventsPreview: byBeacon[item.beaconId]!)
        else
          item,
    ];
  }

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
  ranked.effective_activity_at < \$2::timestamptz
  OR (
    ranked.effective_activity_at = \$2::timestamptz
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
        AND act.seen_at IS NULL
    ) AS unseen
  FROM eligible_pinned ep
  JOIN public.inbox_item ii
    ON ii.user_id = \$1
   AND ii.beacon_id = ep.beacon_id
  LEFT JOIN beacon_activity_stats stats ON stats.beacon_id = ep.beacon_id
)
SELECT *
FROM ranked
WHERE true
  $cursorClause
ORDER BY ranked.effective_activity_at DESC, ranked.beacon_id DESC
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
            createdAt: items.last.effectiveActivityAt,
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
        r'''
WITH visible_raw AS (
  SELECT outbox.*
  FROM public.visible_attention_receipts($1) authorized
  JOIN public.notification_outbox outbox
    ON outbox.id = authorized.receipt_id
),
scope AS (
  SELECT beacon_id FROM public.responsibility_scope_base_beacons($1)
  UNION
  SELECT DISTINCT visible_raw.beacon_id
  FROM visible_raw
  WHERE visible_raw.requires_action
    AND visible_raw.settlement_kind IS NULL
    AND visible_raw.beacon_id IS NOT NULL
),
visible AS (
  SELECT
    visible_raw.id,
    visible_raw.seen_at,
    CASE
      WHEN visible_raw.beacon_id IS NOT NULL
       AND visible_raw.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN 'myWork'
      ELSE 'activity'
    END AS surface
  FROM visible_raw
),
targets AS (
  SELECT id
  FROM visible
  WHERE seen_at IS NULL
    AND ($2::text IS NULL OR surface = $2)
)
UPDATE public.notification_outbox outbox
SET
  seen_at = COALESCE(outbox.seen_at, now())
FROM targets
WHERE outbox.account_id = $1
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
''',
    variables: [
      Variable<String>(accountId),
      Variable<String>(receiptId),
      Variable<String>(kind.wireName),
      Variable<String>(_reviewOpenedEventType),
    ],
    updateKind: UpdateKind.update,
  );
}
