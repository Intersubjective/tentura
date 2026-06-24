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
beacon_id, coordination_item_id, actor_user_id
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
ON CONFLICT (dedup_key) WHERE read_at IS NULL
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
  Future<List<NotificationOutboxItemEntity>> feedForAccount({
    required String accountId,
    int limit = 50,
    DateTime? before,
  }) async {
    final variables = <Variable>[Variable<String>(accountId)];
    final sql = StringBuffer(
      'SELECT $_columns FROM public.notification_outbox WHERE account_id = ',
    )..write(r'$1 ');
    if (before != null) {
      variables.add(Variable<String>(before.toUtc().toIso8601String()));
      sql.write(r'AND created_at < $2::timestamptz ');
    }
    variables.add(Variable<int>(limit));
    sql.write('ORDER BY created_at DESC LIMIT \$${variables.length}');

    final rows =
        await _database.customSelect(sql.toString(), variables: variables)
            .get();
    return [for (final row in rows) _mapRow(row)];
  }

  @override
  Future<int> unreadActionableCount(String accountId) async {
    final row = await _database.customSelect(
      'SELECT COUNT(*)::int AS c FROM public.notification_outbox '
      r'WHERE account_id = $1 AND read_at IS NULL AND category = $2',
      variables: [
        Variable<String>(accountId),
        Variable<String>(NotificationCategory.asksOfMe.name),
      ],
    ).getSingle();
    return row.read<int>('c');
  }

  @override
  Future<int> markRead({
    required String accountId,
    required List<String> ids,
  }) async {
    if (ids.isEmpty) {
      return 0;
    }
    final placeholders =
        List.generate(ids.length, (i) => '\$${i + 2}').join(',');
    return _database.customUpdate(
      'UPDATE public.notification_outbox SET read_at = now() '
      r'WHERE account_id = $1 AND read_at IS NULL '
      'AND id IN ($placeholders)',
      variables: [
        Variable<String>(accountId),
        for (final id in ids) Variable<String>(id),
      ],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<int> markAllRead(String accountId) => _database.customUpdate(
        'UPDATE public.notification_outbox SET read_at = now() '
        r'WHERE account_id = $1 AND read_at IS NULL',
        variables: [Variable<String>(accountId)],
        updateKind: UpdateKind.update,
      );

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
    final placeholders =
        List.generate(ids.length, (i) => '\$${i + 1}').join(',');
    return _database.customUpdate(
      'UPDATE public.notification_outbox SET emailed_at = now() '
      'WHERE emailed_at IS NULL AND id IN ($placeholders)',
      variables: [for (final id in ids) Variable<String>(id)],
      updateKind: UpdateKind.update,
    );
  }

  @override
  Future<List<String>> accountsWithPendingEmail() async {
    final rows = await _database.customSelect(
      'SELECT DISTINCT account_id FROM public.notification_outbox '
      'WHERE emailed_at IS NULL',
    ).get();
    return [for (final row in rows) row.read<String>('account_id')];
  }

  @override
  Future<DateTime?> lastEmailedAt(String accountId) async {
    final rows = await _database.customSelect(
      'SELECT MAX(emailed_at) AS m FROM public.notification_outbox '
      r'WHERE account_id = $1',
      variables: [Variable<String>(accountId)],
    ).get();
    return rows.isEmpty ? null : rows.first.readNullable<DateTime>('m');
  }

  @override
  Future<List<NotificationOutboxItemEntity>> pendingForAccount(
    String accountId,
  ) async {
    final rows = await _database.customSelect(
      'SELECT $_columns FROM public.notification_outbox '
      r'WHERE account_id = $1 AND emailed_at IS NULL '
      'ORDER BY created_at DESC',
      variables: [Variable<String>(accountId)],
    ).get();
    return [for (final row in rows) _mapRow(row)];
  }

  @override
  Future<int> countRecentEmailsByCategory({
    required String accountId,
    required NotificationCategory category,
    required Duration window,
  }) async {
    final since = DateTime.timestamp().subtract(window);
    final row = await _database.customSelect(
      'SELECT COUNT(*)::int AS c FROM public.notification_outbox '
      r'WHERE account_id = $1 AND category = $2 '
      r'AND emailed_at IS NOT NULL AND emailed_at >= $3::timestamptz',
      variables: [
        Variable<String>(accountId),
        Variable<String>(category.name),
        Variable<String>(since.toUtc().toIso8601String()),
      ],
    ).getSingle();
    return row.read<int>('c');
  }

  @override
  Future<int> deleteSettledOlderThan(Duration age) async {
    final before = DateTime.timestamp().subtract(age);
    return _database.customUpdate(
      'DELETE FROM public.notification_outbox '
      r'WHERE read_at IS NOT NULL AND created_at < $1::timestamptz',
      variables: [Variable<String>(before.toUtc().toIso8601String())],
      updateKind: UpdateKind.delete,
    );
  }

  NotificationOutboxItemEntity _mapRow(QueryRow row) =>
      NotificationOutboxItemEntity(
        id: row.read<String>('id'),
        accountId: row.read<String>('account_id'),
        category: notificationCategoryFromName(row.read<String>('category')) ??
            NotificationCategory.coordination,
        kind: _kindFromName(row.read<String>('kind')),
        priority: _priorityFromName(row.read<String>('priority')),
        title: row.read<String>('title'),
        body: row.read<String>('body'),
        actionUrl: row.read<String>('action_url'),
        createdAt: row.read<DateTime>('created_at'),
        readAt: row.readNullable<DateTime>('read_at'),
        collapsedCount: row.read<int>('collapsed_count'),
        beaconId: row.readNullable<String>('beacon_id'),
        coordinationItemId: row.readNullable<String>('coordination_item_id'),
        actorUserId: row.readNullable<String>('actor_user_id'),
      );

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
