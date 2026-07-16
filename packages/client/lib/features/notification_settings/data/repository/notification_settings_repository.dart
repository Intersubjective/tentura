import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/notification_settings.dart';
import '../gql/_g/notification_preferences_fetch.req.gql.dart';
import '../gql/_g/notification_preferences_update.req.gql.dart';

@Singleton(env: [Environment.dev, Environment.prod])
class NotificationSettingsRepository {
  const NotificationSettingsRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'NotificationSettings';

  Future<NotificationSettings> fetch() async {
    final data = await _remoteApiService
        .request(GNotificationPreferencesFetchReq())
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    return _map(
      pushCategories: data.notificationPreferences.pushCategories,
      emailCategories: data.notificationPreferences.emailCategories,
      quietHoursStart: data.notificationPreferences.quietHoursStart,
      quietHoursEnd: data.notificationPreferences.quietHoursEnd,
      tzOffsetMinutes: data.notificationPreferences.tzOffsetMinutes,
      emailDigest: data.notificationPreferences.emailDigest,
      snoozeUntil: data.notificationPreferences.snoozeUntil,
      lockScreenSafe: data.notificationPreferences.lockScreenSafe,
      mutedInAppEventClasses:
          data.notificationPreferences.mutedInAppEventClasses,
    );
  }

  Future<NotificationSettings> update(
    NotificationSettings settings, {
    bool clearQuietHours = false,
    bool clearSnooze = false,
  }) async {
    final data = await _remoteApiService
        .request(
          GNotificationPreferencesUpdateReq(
            (r) => r
              ..vars.pushCategories.replace(
                settings.pushCategories.map((e) => e.name),
              )
              ..vars.emailCategories.replace(
                settings.emailCategories.map((e) => e.name),
              )
              ..vars.quietHoursStart = settings.quietHoursStart
              ..vars.quietHoursEnd = settings.quietHoursEnd
              ..vars.clearQuietHours = clearQuietHours
              ..vars.tzOffsetMinutes = settings.tzOffsetMinutes
              ..vars.emailDigest = settings.emailDigest.name
              ..vars.snoozeUntil = settings.snoozeUntil
                  ?.toUtc()
                  .toIso8601String()
              ..vars.clearSnooze = clearSnooze
              ..vars.lockScreenSafe = settings.lockScreenSafe
              ..vars.mutedInAppEventClasses.replace(
                settings.mutedInAppEventClasses.map((e) => e.name),
              ),
          ),
        )
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label));
    final p = data.notificationPreferencesUpdate;
    return _map(
      pushCategories: p.pushCategories,
      emailCategories: p.emailCategories,
      quietHoursStart: p.quietHoursStart,
      quietHoursEnd: p.quietHoursEnd,
      tzOffsetMinutes: p.tzOffsetMinutes,
      emailDigest: p.emailDigest,
      snoozeUntil: p.snoozeUntil,
      lockScreenSafe: p.lockScreenSafe,
      mutedInAppEventClasses: p.mutedInAppEventClasses,
    );
  }

  NotificationSettings _map({
    required Iterable<String> pushCategories,
    required Iterable<String> emailCategories,
    required int? quietHoursStart,
    required int? quietHoursEnd,
    required int tzOffsetMinutes,
    required String emailDigest,
    required String? snoozeUntil,
    required bool lockScreenSafe,
    required Iterable<String> mutedInAppEventClasses,
  }) => NotificationSettings(
    pushCategories: _parse(pushCategories),
    emailCategories: _parse(emailCategories),
    quietHoursStart: quietHoursStart,
    quietHoursEnd: quietHoursEnd,
    tzOffsetMinutes: tzOffsetMinutes,
    emailDigest: digestFromName(emailDigest),
    lockScreenSafe: lockScreenSafe,
    mutedInAppEventClasses: {
      for (final value in mutedInAppEventClasses)
        ?NotificationSettings.inAppClassFromName(value),
    },
    snoozeUntil: snoozeUntil == null ? null : DateTime.tryParse(snoozeUntil),
  );

  Set<NotificationSettingsCategory> _parse(Iterable<String> names) => {
    for (final n in names) ?NotificationSettings.categoryFromName(n),
  };
}
