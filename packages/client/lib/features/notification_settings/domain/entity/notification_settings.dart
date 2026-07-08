/// The four notification categories, in display order (mirrors the server).
enum NotificationSettingsCategory {
  asksOfMe,
  unblocksMe,
  coordination,
  connections,
  ambient;
}

/// Email digest cadence (mirrors the server `DigestCadence`).
enum NotificationDigestCadence { off, daily, weekly }

NotificationDigestCadence digestFromName(String? name) {
  for (final c in NotificationDigestCadence.values) {
    if (c.name == name) {
      return c;
    }
  }
  return NotificationDigestCadence.off;
}

/// Account notification preferences, as edited by the settings screen.
class NotificationSettings {
  const NotificationSettings({
    required this.pushCategories,
    required this.emailCategories,
    required this.tzOffsetMinutes,
    required this.emailDigest,
    required this.lockScreenSafe,
    this.quietHoursStart,
    this.quietHoursEnd,
    this.snoozeUntil,
  });

  factory NotificationSettings.empty() => const NotificationSettings(
        pushCategories: {},
        emailCategories: {},
        tzOffsetMinutes: 0,
        emailDigest: NotificationDigestCadence.off,
        lockScreenSafe: false,
      );

  final Set<NotificationSettingsCategory> pushCategories;
  final Set<NotificationSettingsCategory> emailCategories;
  final int? quietHoursStart;
  final int? quietHoursEnd;
  final int tzOffsetMinutes;
  final NotificationDigestCadence emailDigest;
  final bool lockScreenSafe;
  final DateTime? snoozeUntil;

  bool get hasQuietHours => quietHoursStart != null && quietHoursEnd != null;

  bool isEnabled(NotificationSettingsCategory c, {required bool email}) =>
      (email ? emailCategories : pushCategories).contains(c);

  NotificationSettings copyWith({
    Set<NotificationSettingsCategory>? pushCategories,
    Set<NotificationSettingsCategory>? emailCategories,
    int? quietHoursStart,
    int? quietHoursEnd,
    bool clearQuietHours = false,
    int? tzOffsetMinutes,
    NotificationDigestCadence? emailDigest,
    bool? lockScreenSafe,
    DateTime? snoozeUntil,
    bool clearSnooze = false,
  }) =>
      NotificationSettings(
        pushCategories: pushCategories ?? this.pushCategories,
        emailCategories: emailCategories ?? this.emailCategories,
        quietHoursStart:
            clearQuietHours ? null : (quietHoursStart ?? this.quietHoursStart),
        quietHoursEnd:
            clearQuietHours ? null : (quietHoursEnd ?? this.quietHoursEnd),
        tzOffsetMinutes: tzOffsetMinutes ?? this.tzOffsetMinutes,
        emailDigest: emailDigest ?? this.emailDigest,
        lockScreenSafe: lockScreenSafe ?? this.lockScreenSafe,
        snoozeUntil: clearSnooze ? null : (snoozeUntil ?? this.snoozeUntil),
      );

  static NotificationSettingsCategory? categoryFromName(String name) {
    for (final c in NotificationSettingsCategory.values) {
      if (c.name == name) {
        return c;
      }
    }
    return null;
  }
}
