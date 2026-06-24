import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/beacon_mute_entity.dart';
import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';

import '../database/tentura_db.dart';

@Singleton(
  as: NotificationPreferenceRepositoryPort,
  env: [Environment.dev, Environment.prod],
)
class NotificationPreferenceRepository
    implements NotificationPreferenceRepositoryPort {
  const NotificationPreferenceRepository(this._database);

  final TenturaDb _database;

  // Categories are stored as text[]; read/write them as a comma-joined string
  // to avoid array type-mapping in customSelect/customStatement.
  static const _selectColumns = '''
account_id,
array_to_string(push_categories, ',')  AS push_categories,
array_to_string(email_categories, ',') AS email_categories,
quiet_hours_start, quiet_hours_end, tz_offset_minutes,
email_digest, snooze_until, lock_screen_safe, locale
''';

  @override
  Future<NotificationPreferencesEntity> getForAccount(String accountId) async {
    final rows = await _database.customSelect(
      'SELECT $_selectColumns FROM public.notification_preference '
      r'WHERE account_id = $1 LIMIT 1',
      variables: [Variable<String>(accountId)],
    ).get();
    if (rows.isEmpty) {
      return NotificationPreferencesEntity.defaults(accountId);
    }
    return _mapRow(rows.first);
  }

  @override
  Future<Map<String, NotificationPreferencesEntity>> getForAccounts(
    Set<String> accountIds,
  ) async {
    if (accountIds.isEmpty) {
      return const {};
    }
    final ids = accountIds.toList();
    final placeholders =
        List.generate(ids.length, (i) => '\$${i + 1}').join(',');
    final rows = await _database.customSelect(
      'SELECT $_selectColumns FROM public.notification_preference '
      'WHERE account_id IN ($placeholders)',
      variables: [for (final id in ids) Variable<String>(id)],
    ).get();
    final out = <String, NotificationPreferencesEntity>{
      for (final id in ids) id: NotificationPreferencesEntity.defaults(id),
    };
    for (final row in rows) {
      final entity = _mapRow(row);
      out[entity.accountId] = entity;
    }
    return out;
  }

  @override
  Future<void> upsert(NotificationPreferencesEntity prefs) async {
    await _database.customStatement(
      r'''
INSERT INTO public.notification_preference (
  account_id, push_categories, email_categories,
  quiet_hours_start, quiet_hours_end, tz_offset_minutes,
  email_digest, snooze_until, lock_screen_safe, locale, updated_at
) VALUES (
  $1,
  string_to_array($2, ','),
  string_to_array($3, ','),
  $4, $5, $6,
  $7,
  CASE WHEN $8 = '' THEN NULL ELSE $8::timestamptz END,
  $9, $10, now()
)
ON CONFLICT (account_id) DO UPDATE SET
  push_categories   = EXCLUDED.push_categories,
  email_categories  = EXCLUDED.email_categories,
  quiet_hours_start = EXCLUDED.quiet_hours_start,
  quiet_hours_end   = EXCLUDED.quiet_hours_end,
  tz_offset_minutes = EXCLUDED.tz_offset_minutes,
  email_digest      = EXCLUDED.email_digest,
  snooze_until      = EXCLUDED.snooze_until,
  lock_screen_safe  = EXCLUDED.lock_screen_safe,
  locale            = EXCLUDED.locale,
  updated_at        = now()
''',
      [
        prefs.accountId,
        prefs.pushCategories.map((c) => c.name).join(','),
        prefs.emailCategories.map((c) => c.name).join(','),
        prefs.quietHoursStartMinute,
        prefs.quietHoursEndMinute,
        prefs.tzOffsetMinutes,
        prefs.emailDigest.name,
        prefs.snoozeUntil?.toUtc().toIso8601String() ?? '',
        prefs.lockScreenSafe,
        prefs.locale,
      ],
    );
  }

  @override
  Future<List<BeaconMuteEntity>> getBeaconMutes(String accountId) async {
    final rows = await _database.customSelect(
      'SELECT account_id, beacon_id, muted_until '
      'FROM public.notification_beacon_mute '
      r'WHERE account_id = $1',
      variables: [Variable<String>(accountId)],
    ).get();
    return [
      for (final row in rows)
        BeaconMuteEntity(
          accountId: row.read<String>('account_id'),
          beaconId: row.read<String>('beacon_id'),
          mutedUntil: row.readNullable<DateTime>('muted_until'),
        ),
    ];
  }

  @override
  Future<Set<String>> getMutedBeaconIds(String accountId, DateTime now) async {
    final rows = await _database.customSelect(
      'SELECT beacon_id FROM public.notification_beacon_mute '
      r'WHERE account_id = $1 AND (muted_until IS NULL OR muted_until > $2::timestamptz)',
      variables: [
        Variable<String>(accountId),
        Variable<String>(now.toUtc().toIso8601String()),
      ],
    ).get();
    return {for (final row in rows) row.read<String>('beacon_id')};
  }

  @override
  Future<void> setBeaconMute({
    required String accountId,
    required String beaconId,
    DateTime? mutedUntil,
  }) async {
    await _database.customStatement(
      r'''
INSERT INTO public.notification_beacon_mute (account_id, beacon_id, muted_until)
VALUES ($1, $2, CASE WHEN $3 = '' THEN NULL ELSE $3::timestamptz END)
ON CONFLICT (account_id, beacon_id)
DO UPDATE SET muted_until = EXCLUDED.muted_until
''',
      [
        accountId,
        beaconId,
        mutedUntil?.toUtc().toIso8601String() ?? '',
      ],
    );
  }

  @override
  Future<void> clearBeaconMute({
    required String accountId,
    required String beaconId,
  }) async {
    await _database.customStatement(
      'DELETE FROM public.notification_beacon_mute '
      r'WHERE account_id = $1 AND beacon_id = $2',
      [accountId, beaconId],
    );
  }

  NotificationPreferencesEntity _mapRow(QueryRow row) {
    Set<NotificationCategory> parseCategories(String? joined) {
      if (joined == null || joined.isEmpty) {
        return const {};
      }
      return {
        for (final name in joined.split(','))
          ?notificationCategoryFromName(name),
      };
    }

    return NotificationPreferencesEntity(
      accountId: row.read<String>('account_id'),
      pushCategories: parseCategories(row.readNullable<String>('push_categories')),
      emailCategories:
          parseCategories(row.readNullable<String>('email_categories')),
      quietHoursStartMinute: row.readNullable<int>('quiet_hours_start'),
      quietHoursEndMinute: row.readNullable<int>('quiet_hours_end'),
      tzOffsetMinutes: row.read<int>('tz_offset_minutes'),
      emailDigest: digestCadenceFromName(row.read<String>('email_digest')),
      snoozeUntil: row.readNullable<DateTime>('snooze_until'),
      lockScreenSafe: row.read<bool>('lock_screen_safe'),
      locale: row.read<String>('locale'),
    );
  }
}
