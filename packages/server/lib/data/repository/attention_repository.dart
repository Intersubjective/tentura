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

import '../database/tentura_db.dart';

@Singleton(as: AttentionQueryPort)
class AttentionRepository implements AttentionQueryPort {
  const AttentionRepository(this._database);

  final TenturaDb _database;

  @override
  Future<AttentionFeed> attentionFeed({
    required String accountId,
    required AttentionFeedView view,
    AttentionCursor? cursor,
    int limit = 50,
  }) async {
    final boundedLimit = limit.clamp(1, 100);
    final variables = <Variable>[
      Variable<String>(accountId),
      Variable<String>(view.name),
    ];
    final cursorClause = StringBuffer();
    if (cursor != null) {
      variables
        ..add(Variable<String>(cursor.createdAt.toUtc().toIso8601String()))
        ..add(Variable<String>(cursor.id));
      cursorClause.write(
        r'''
AND (
  visible.created_at < $3::timestamptz
  OR (visible.created_at = $3::timestamptz AND visible.id < $4)
)''',
      );
    }
    variables.add(Variable<int>(boundedLimit + 1));
    final limitParameter = '\$${variables.length}';

    final rows = await _database.customSelect(
      '''
WITH visible AS MATERIALIZED (
  SELECT outbox.*, authorized.tombstone_copy
  FROM public.visible_attention_receipts(\$1) authorized
  JOIN public.notification_outbox outbox
    ON outbox.id = authorized.receipt_id
),
summary AS (
  SELECT COUNT(*) FILTER (
    WHERE COALESCE(seen_at, read_at) IS NULL
  )::int AS unread_total
  FROM visible
),
page AS (
  SELECT visible.*
  FROM visible
  WHERE (\$2 = 'all' OR COALESCE(visible.seen_at, visible.read_at) IS NULL)
    $cursorClause
  ORDER BY visible.created_at DESC, visible.id DESC
  LIMIT $limitParameter
)
SELECT summary.unread_total, page.*
FROM summary
LEFT JOIN LATERAL (SELECT * FROM page) page ON true
ORDER BY page.created_at DESC NULLS LAST, page.id DESC NULLS LAST
''',
      variables: variables,
    ).get();

    final unreadTotal = rows.isEmpty ? 0 : rows.first.read<int>('unread_total');
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
      summary: AttentionSummary(unreadTotal: unreadTotal),
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
      seenAt: _readTimestamp(row, 'seen_at') ?? _readTimestamp(row, 'read_at'),
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
  seen_at = COALESCE(outbox.seen_at, outbox.read_at, now()),
  read_at = COALESCE(outbox.read_at, outbox.seen_at, now())
WHERE outbox.account_id = \$1
  AND (outbox.seen_at IS NULL OR outbox.read_at IS NULL)
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
  Future<int> markAllSeen(String accountId) => _database.customUpdate(
    r'''
UPDATE public.notification_outbox outbox
SET
  seen_at = COALESCE(outbox.seen_at, outbox.read_at, now()),
  read_at = COALESCE(outbox.read_at, outbox.seen_at, now())
WHERE outbox.account_id = $1
  AND (outbox.seen_at IS NULL OR outbox.read_at IS NULL)
  AND outbox.id IN (
    SELECT receipt_id
    FROM public.visible_attention_receipts($1)
  )
''',
    variables: [Variable<String>(accountId)],
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
