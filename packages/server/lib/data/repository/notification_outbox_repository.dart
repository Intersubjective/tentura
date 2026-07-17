import 'dart:convert';

import 'package:drift_postgres/drift_postgres.dart' show PgDateTime;
import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/entity/notification_outbox_item_entity.dart';
import 'package:tentura_server/domain/entity/notification_priority.dart';
import 'package:tentura_server/domain/port/notification_outbox_repository_port.dart';

import '../database/tentura_db.dart';

@Singleton(
  as: NotificationOutboxRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class NotificationOutboxRepository implements NotificationOutboxRepositoryPort {
  const NotificationOutboxRepository(this._database);

  final TenturaDb _database;

  static const _columns = '''
id, account_id, category, kind, priority,
title, body, action_url, created_at, read_at, collapsed_count,
beacon_id, coordination_item_id, actor_user_id,
seen_at, source_event_key, destination_kind, target_entity_id,
presentation_key, presentation_payload::text AS presentation_payload,
in_app_preference_class, suppression_class, access_policy
''';

  @override
  Future<void> enqueue({
    required String accountId,
    required NotificationCategory category,
    required NotificationKind kind,
    required NotificationPriority priority,
    required String title,
    required String body,
    required String actionUrl,
    required String dedupKey,
    String? beaconId,
    String? coordinationItemId,
    String? actorUserId,
  }) async {
    await _database.customStatement(
      r'''
INSERT INTO public.notification_outbox (
  id, account_id, category, kind, priority,
  title, body, action_url, dedup_key,
  beacon_id, coordination_item_id, actor_user_id
) VALUES (
  gen_random_uuid()::text, $1, $2, $3, $4,
  $5, $6, $7, $8,
  $9, $10, $11
)
ON CONFLICT (dedup_key) WHERE seen_at IS NULL
DO UPDATE SET
  created_at      = now(),
  collapsed_count = notification_outbox.collapsed_count + 1,
  title           = EXCLUDED.title,
  body            = EXCLUDED.body,
  action_url      = EXCLUDED.action_url,
  priority        = EXCLUDED.priority
''',
      [
        accountId,
        category.name,
        kind.name,
        priority.name,
        title,
        body,
        actionUrl,
        dedupKey,
        beaconId,
        coordinationItemId,
        actorUserId,
      ],
    );
  }

  @override
  Future<int> markEmailedByDedupKey(String dedupKey) => _database.customUpdate(
    'UPDATE public.notification_outbox SET emailed_at = now() '
    r'WHERE dedup_key = $1 AND emailed_at IS NULL',
    variables: [Variable<String>(dedupKey)],
    updateKind: UpdateKind.update,
  );

  @override
  Future<int> markEmailed(List<String> ids) async {
    if (ids.isEmpty) {
      return 0;
    }
    final placeholders = List.generate(
      ids.length,
      (i) => '\$${i + 1}',
    ).join(',');
    return _database.customUpdate(
      'UPDATE public.notification_outbox SET emailed_at = now() '
      'WHERE emailed_at IS NULL AND id IN ($placeholders)',
      variables: [for (final id in ids) Variable<String>(id)],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<List<String>> accountsWithPendingEmail() async {
    final rows = await _database
        .customSelect(
          'SELECT DISTINCT account_id FROM public.notification_outbox '
          'WHERE emailed_at IS NULL',
        )
        .get();
    return [for (final row in rows) row.read<String>('account_id')];
  }

  @override
  Future<DateTime?> lastEmailedAt(String accountId) async {
    final rows = await _database
        .customSelect(
          'SELECT MAX(emailed_at) AS m FROM public.notification_outbox '
          r'WHERE account_id = $1',
          variables: [Variable<String>(accountId)],
        )
        .get();
    return rows.isEmpty ? null : _readTimestamp(rows.first, 'm');
  }

  @override
  Future<List<NotificationOutboxItemEntity>> pendingForAccount(
    String accountId,
  ) async {
    final rows = await _database
        .customSelect(
          'SELECT $_columns FROM public.notification_outbox '
          r'WHERE account_id = $1 AND emailed_at IS NULL '
          'ORDER BY created_at DESC',
          variables: [Variable<String>(accountId)],
        )
        .get();
    return [for (final row in rows) _mapRow(row)];
  }

  @override
  Future<int> countRecentEmailsByCategory({
    required String accountId,
    required NotificationCategory category,
    required Duration window,
  }) async {
    final since = DateTime.timestamp().subtract(window);
    final row = await _database
        .customSelect(
          'SELECT COUNT(*)::int AS c FROM public.notification_outbox '
          r'WHERE account_id = $1 AND category = $2 '
          r'AND emailed_at IS NOT NULL AND emailed_at >= $3::timestamptz',
          variables: [
            Variable<String>(accountId),
            Variable<String>(category.name),
            Variable<String>(since.toUtc().toIso8601String()),
          ],
        )
        .getSingle();
    return row.read<int>('c');
  }

  @override
  Future<int> deleteSettledOlderThan(Duration age) async {
    final before = DateTime.timestamp().subtract(age);
    return _database.customUpdate(
      'DELETE FROM public.notification_outbox '
      r'WHERE seen_at IS NOT NULL AND created_at < $1::timestamptz',
      variables: [Variable<String>(before.toUtc().toIso8601String())],
      updateKind: UpdateKind.delete,
    );
  }

  NotificationOutboxItemEntity _mapRow(QueryRow row) =>
      NotificationOutboxItemEntity(
        id: row.read<String>('id'),
        accountId: row.read<String>('account_id'),
        category:
            notificationCategoryFromName(row.read<String>('category')) ??
            NotificationCategory.coordination,
        kind: _kindFromName(row.read<String>('kind')),
        priority: _priorityFromName(row.read<String>('priority')),
        title: row.read<String>('title'),
        body: row.read<String>('body'),
        actionUrl: row.read<String>('action_url'),
        createdAt: _readTimestamp(row, 'created_at')!,
        readAt: _readTimestamp(row, 'read_at'),
        collapsedCount: row.read<int>('collapsed_count'),
        beaconId: row.readNullable<String>('beacon_id'),
        coordinationItemId: row.readNullable<String>('coordination_item_id'),
        actorUserId: row.readNullable<String>('actor_user_id'),
        seenAt: _readTimestamp(row, 'seen_at'),
        sourceEventKey: row.readNullable<String>('source_event_key'),
        destinationKind: row.readNullable<String>('destination_kind'),
        targetEntityId: row.readNullable<String>('target_entity_id'),
        presentationKey: row.readNullable<String>('presentation_key'),
        presentationPayload: Map<String, Object?>.from(
          jsonDecode(row.read<String>('presentation_payload')) as Map,
        ),
        inAppPreferenceClass: row.readNullable<String>(
          'in_app_preference_class',
        ),
        suppressionClass: row.read<String>('suppression_class'),
        accessPolicy: row.read<String>('access_policy'),
      );

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

  static NotificationKind _kindFromName(String name) =>
      NotificationKind.values.firstWhere(
        (k) => k.name == name,
        orElse: () => NotificationKind.coordinationChanged,
      );

  static NotificationPriority _priorityFromName(String name) =>
      NotificationPriority.values.firstWhere(
        (p) => p.name == name,
        orElse: () => NotificationPriority.normal,
      );
}
