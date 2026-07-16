import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/attention/attention_models.dart';
import 'package:tentura_server/domain/port/notification_preference_repository_port.dart';

/// Read/update account notification preferences with validation.
@injectable
class NotificationPreferenceCase {
  const NotificationPreferenceCase(this._repository);

  final NotificationPreferenceRepositoryPort _repository;

  Future<NotificationPreferencesEntity> getForAccount(String accountId) =>
      _repository.getForAccount(accountId);

  /// Applies a partial update over the account's current preferences. Null
  /// arguments leave the corresponding field untouched.
  Future<NotificationPreferencesEntity> update({
    required String accountId,
    List<String>? pushCategories,
    List<String>? emailCategories,
    int? quietHoursStartMinute,
    int? quietHoursEndMinute,
    bool clearQuietHours = false,
    int? tzOffsetMinutes,
    String? emailDigest,
    DateTime? snoozeUntil,
    bool clearSnooze = false,
    bool? lockScreenSafe,
    String? locale,
    List<String>? mutedInAppEventClasses,
  }) async {
    final current = await _repository.getForAccount(accountId);

    final next = current.copyWith(
      pushCategories: pushCategories == null
          ? current.pushCategories
          : _parseCategories(pushCategories),
      emailCategories: emailCategories == null
          ? current.emailCategories
          : _parseCategories(emailCategories),
      quietHoursStartMinute: clearQuietHours
          ? null
          : (quietHoursStartMinute == null
                ? current.quietHoursStartMinute
                : _validateMinute(quietHoursStartMinute)),
      quietHoursEndMinute: clearQuietHours
          ? null
          : (quietHoursEndMinute == null
                ? current.quietHoursEndMinute
                : _validateMinute(quietHoursEndMinute)),
      tzOffsetMinutes: tzOffsetMinutes ?? current.tzOffsetMinutes,
      emailDigest: emailDigest == null
          ? current.emailDigest
          : digestCadenceFromName(emailDigest),
      snoozeUntil: clearSnooze ? null : (snoozeUntil ?? current.snoozeUntil),
      lockScreenSafe: lockScreenSafe ?? current.lockScreenSafe,
      locale: locale ?? current.locale,
      mutedInAppEventClasses: mutedInAppEventClasses == null
          ? current.mutedInAppEventClasses
          : _parseMutedInAppEventClasses(mutedInAppEventClasses),
    );

    await _repository.upsert(next);
    return next;
  }

  Future<void> setBeaconMute({
    required String accountId,
    required String beaconId,
    DateTime? mutedUntil,
  }) => _repository.setBeaconMute(
    accountId: accountId,
    beaconId: beaconId,
    mutedUntil: mutedUntil,
  );

  Future<void> clearBeaconMute({
    required String accountId,
    required String beaconId,
  }) => _repository.clearBeaconMute(accountId: accountId, beaconId: beaconId);

  Set<NotificationCategory> _parseCategories(List<String> names) => {
    for (final name in names) ?notificationCategoryFromName(name),
  };

  Set<String> _parseMutedInAppEventClasses(List<String> names) => {
    for (final name in names) _parseMuteableClass(name),
  };

  String _parseMuteableClass(String name) {
    for (final value in AttentionPreferenceClass.values) {
      if (value.wireName == name) return value.wireName;
    }
    throw ArgumentError.value(
      name,
      'mutedInAppEventClasses',
      'unknown or non-muteable attention preference class',
    );
  }

  int _validateMinute(int minute) {
    if (minute < 0 || minute >= 1440) {
      throw ArgumentError.value(
        minute,
        'minute',
        'quiet-hours minute must be in [0, 1440)',
      );
    }
    return minute;
  }
}
