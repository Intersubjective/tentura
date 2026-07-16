import 'package:freezed_annotation/freezed_annotation.dart';

import 'digest_cadence.dart';
import 'notification_category.dart';

part 'notification_preferences_entity.freezed.dart';

/// Account-scoped notification preferences.
///
/// Push/email opt-in is expressed per [NotificationCategory] (the user-facing
/// control granularity). Quiet hours are stored as minutes-of-day in the
/// account's own timezone via [tzOffsetMinutes].
@freezed
abstract class NotificationPreferencesEntity
    with _$NotificationPreferencesEntity {
  const factory NotificationPreferencesEntity({
    required String accountId,
    @Default({}) Set<NotificationCategory> pushCategories,
    @Default({}) Set<NotificationCategory> emailCategories,
    @Default(<String>{}) Set<String> mutedInAppEventClasses,

    /// Minutes-of-day [0, 1440) for the start/end of quiet hours, in local
    /// time. Both null means quiet hours are disabled.
    int? quietHoursStartMinute,
    int? quietHoursEndMinute,
    @Default(0) int tzOffsetMinutes,
    @Default(DigestCadence.off) DigestCadence emailDigest,

    /// Global snooze: suppress all push/email until this instant.
    DateTime? snoozeUntil,

    /// When true, push copy is reduced to a privacy-safe summary (no excerpt).
    @Default(false) bool lockScreenSafe,

    /// Preferred email locale, e.g. 'en' or 'ru'. Defaults to English.
    @Default('en') String locale,
  }) = _NotificationPreferencesEntity;

  const NotificationPreferencesEntity._();

  /// Conservative defaults (see strategy A1): push for everything except
  /// ambient; email opt-in only for the highest-stakes asksOfMe; digest off.
  factory NotificationPreferencesEntity.defaults(String accountId) =>
      NotificationPreferencesEntity(
        accountId: accountId,
        pushCategories: const {
          NotificationCategory.asksOfMe,
          NotificationCategory.unblocksMe,
          NotificationCategory.coordination,
          NotificationCategory.connections,
        },
        emailCategories: const {
          NotificationCategory.asksOfMe,
          NotificationCategory.connections,
        },
      );

  bool get hasQuietHours =>
      quietHoursStartMinute != null && quietHoursEndMinute != null;

  /// Whether [now] falls inside the configured quiet-hours window (handles a
  /// window that wraps past midnight).
  bool isWithinQuietHours(DateTime now) {
    final start = quietHoursStartMinute;
    final end = quietHoursEndMinute;
    if (start == null || end == null || start == end) {
      return false;
    }
    final local = now.toUtc().add(Duration(minutes: tzOffsetMinutes));
    final minutes = local.hour * 60 + local.minute;
    if (start < end) {
      return minutes >= start && minutes < end;
    }
    return minutes >= start || minutes < end;
  }

  bool get isSnoozed => snoozeUntil != null;

  bool isSnoozedAt(DateTime now) =>
      snoozeUntil != null && now.isBefore(snoozeUntil!);
}
