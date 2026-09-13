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

  static const _activityPageStreamCte = '''
page_stream AS (
  SELECT
    $_visibleStreamColumns,
    'receipt'::text AS item_kind,
    NULL::text AS forward_outcome,
    NULL::int AS forward_count,
    NULL::int AS digest_count
  FROM visible v
  WHERE v.surface = 'activity'
    AND (
      v.beacon_id IS NULL
      OR v.presentation_key IS DISTINCT FROM 'relay_received'
      OR NOT EXISTS (
        SELECT 1
        FROM public.inbox_item ii
        WHERE ii.user_id = \$1
          AND ii.beacon_id = v.beacon_id
      )
    )

  UNION ALL

  SELECT
    ('inbox:' || ii.beacon_id) AS id,
    \$1::text AS account_id,
    'coordination'::text AS category,
    'newRelay'::text AS kind,
    'normal'::text AS priority,
    CASE
      WHEN public.beacon_can_read_content(ii.beacon_id, \$1)
      THEN COALESCE(b.title, '')
      ELSE ''::text
    END AS title,
    ''::text AS body,
    ('/#/view?id=' || ii.beacon_id) AS action_url,
    ii.latest_forward_at AS created_at,
    0 AS collapsed_count,
    ii.beacon_id,
    NULL::text AS coordination_item_id,
    NULL::text AS actor_user_id,
    CASE
      WHEN ii.beacon_id IN (SELECT scope.beacon_id FROM scope)
      THEN ii.latest_forward_at
      WHEN EXISTS (
        SELECT 1
        FROM visible relay
        WHERE relay.beacon_id = ii.beacon_id
          AND relay.seen_at IS NULL
          AND relay.presentation_key = 'relay_received'
      )
      THEN NULL::timestamptz
      ELSE ii.latest_forward_at
    END AS seen_at,
    NULL::text AS source_event_key,
    'beacon'::text AS destination_kind,
    ii.beacon_id AS target_entity_id,
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
      NOT public.beacon_can_read_content(ii.beacon_id, \$1)
      AND NOT (
        ii.status IN (3, 4)
        AND public.beacon_can_read_tombstone(ii.beacon_id, \$1)
      )
    ) AS tombstone_copy,
    'activity'::text AS surface,
    'forward'::text AS item_kind,
    CASE
      WHEN ii.beacon_id IN (SELECT scope.beacon_id FROM scope) THEN 'helping'
      WHEN ii.status = 1 THEN 'watching'
      WHEN ii.status = 2 THEN 'notInterested'
      WHEN ii.status = 3 THEN 'closedBeforeResponse'
      WHEN ii.status = 4 THEN 'deletedBeforeResponse'
      ELSE NULL::text
    END AS forward_outcome,
    ii.forward_count AS forward_count,
    NULL::int AS digest_count
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
    AND NOT (
      ii.status = 1
      AND ii.beacon_id NOT IN (SELECT scope.beacon_id FROM scope)
      AND EXISTS (
        SELECT 1
        FROM visible newer
        WHERE newer.beacon_id = ii.beacon_id
          AND newer.seen_at IS NULL
          AND newer.created_at > ii.latest_forward_at
      )
    )

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
    digest.beacon_count AS digest_count
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
    final items = <AttentionReceipt>[
      for (final row in rows)
        if (row.data['id'] != null) _mapRow(row),
    ];
    final hasMore = items.length > boundedLimit;
    if (hasMore) {
      items.removeLast();
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
WHERE outbox.id = $2
  AND outbox.account_id = $1
  AND outbox.requires_action
  AND outbox.settlement_kind IS NULL
  AND outbox.id IN (
    SELECT receipt_id
    FROM public.visible_attention_receipts($1)
  )
  AND ($3 <> 'dismissed' OR outbox.suppression_class <> 'mandatory')
''',
    variables: [
      Variable<String>(accountId),
      Variable<String>(receiptId),
      Variable<String>(kind.wireName),
    ],
    updateKind: UpdateKind.update,
  );
}
