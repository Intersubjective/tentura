import 'package:test/test.dart';

import 'package:tentura_root/domain/enums.dart';

import 'package:tentura_server/domain/entity/digest_cadence.dart';
import 'package:tentura_server/domain/entity/notification_category.dart';
import 'package:tentura_server/domain/entity/notification_channel.dart';
import 'package:tentura_server/domain/entity/notification_preferences_entity.dart';
import 'package:tentura_server/domain/entity/user_presence_entity.dart';
import 'package:tentura_server/domain/notification/notification_preference_gate.dart';

void main() {
  const gate = NotificationPreferenceGate();
  final now = DateTime.utc(2026, 6, 24, 12); // noon UTC

  NotificationPreferencesEntity prefs({
    Set<NotificationCategory>? push,
    Set<NotificationCategory>? email,
    int? quietStart,
    int? quietEnd,
    int tzOffsetMinutes = 0,
    DigestCadence digest = DigestCadence.off,
    DateTime? snoozeUntil,
  }) =>
      NotificationPreferencesEntity(
        accountId: 'a1',
        pushCategories: push ?? const {NotificationCategory.asksOfMe},
        emailCategories: email ?? const {},
        quietHoursStartMinute: quietStart,
        quietHoursEndMinute: quietEnd,
        tzOffsetMinutes: tzOffsetMinutes,
        emailDigest: digest,
        snoozeUntil: snoozeUntil,
      );

  // A "present" user: online and already notified, not due for re-notify.
  // shouldNotify reads the real wall clock, so use clearly-past timestamps to
  // keep the fixture deterministic.
  final presentUser = UserPresenceEntity(
    userId: 'u1',
    lastSeenAt: DateTime.utc(2020),
    lastNotifiedAt: DateTime.utc(2020, 1, 1, 0, 0, 1),
    offlineAfterDelay: const Duration(minutes: 5),
    status: UserPresenceStatus.online,
  );

  group('allowsChannel', () {
    test('allows when category is enabled for the channel', () {
      expect(
        gate.allowsChannel(
          channel: NotificationChannel.push,
          category: NotificationCategory.asksOfMe,
          prefs: prefs(push: const {NotificationCategory.asksOfMe}),
          now: now,
        ),
        isTrue,
      );
    });

    test('blocks when category is not enabled for the channel', () {
      expect(
        gate.allowsChannel(
          channel: NotificationChannel.push,
          category: NotificationCategory.ambient,
          prefs: prefs(push: const {NotificationCategory.asksOfMe}),
          now: now,
        ),
        isFalse,
      );
    });

    test('blocks while globally snoozed', () {
      expect(
        gate.allowsChannel(
          channel: NotificationChannel.push,
          category: NotificationCategory.asksOfMe,
          prefs: prefs(
            push: const {NotificationCategory.asksOfMe},
            snoozeUntil: now.add(const Duration(hours: 1)),
          ),
          now: now,
        ),
        isFalse,
      );
    });

    test('blocks a muted beacon', () {
      expect(
        gate.allowsChannel(
          channel: NotificationChannel.push,
          category: NotificationCategory.asksOfMe,
          prefs: prefs(push: const {NotificationCategory.asksOfMe}),
          now: now,
          beaconId: 'b1',
          mutedBeaconIds: const {'b1'},
        ),
        isFalse,
      );
    });

    test('blocks during quiet hours', () {
      // Window 11:00-13:00 local (UTC), noon is inside.
      expect(
        gate.allowsChannel(
          channel: NotificationChannel.push,
          category: NotificationCategory.asksOfMe,
          prefs: prefs(
            push: const {NotificationCategory.asksOfMe},
            quietStart: 11 * 60,
            quietEnd: 13 * 60,
          ),
          now: now,
        ),
        isFalse,
      );
    });
  });

  group('quiet hours wraparound', () {
    test('window crossing midnight contains early-morning time', () {
      // 22:00 -> 07:00 local; test at 02:00 UTC.
      final p = prefs(quietStart: 22 * 60, quietEnd: 7 * 60);
      expect(p.isWithinQuietHours(DateTime.utc(2026, 6, 24, 2)), isTrue);
      expect(p.isWithinQuietHours(DateTime.utc(2026, 6, 24, 12)), isFalse);
    });

    test('tz offset shifts the local window', () {
      // +180 min: 12:00 UTC -> 15:00 local. Window 14:00-16:00 local.
      final p = prefs(
        quietStart: 14 * 60,
        quietEnd: 16 * 60,
        tzOffsetMinutes: 180,
      );
      expect(p.isWithinQuietHours(now), isTrue);
    });
  });

  group('decideEmail', () {
    test('none when category email-disabled', () {
      expect(
        gate.decideEmail(
          category: NotificationCategory.asksOfMe,
          prefs: prefs(email: const {}),
          presence: presentUser,
          pushDelivered: true,
          now: now,
        ),
        EmailDecision.none,
      );
    });

    test('immediate for asksOfMe when push not delivered', () {
      expect(
        gate.decideEmail(
          category: NotificationCategory.asksOfMe,
          prefs: prefs(email: const {NotificationCategory.asksOfMe}),
          presence: presentUser,
          pushDelivered: false,
          now: now,
        ),
        EmailDecision.immediate,
      );
    });

    test('immediate for asksOfMe when user absent even if push delivered', () {
      expect(
        gate.decideEmail(
          category: NotificationCategory.asksOfMe,
          prefs: prefs(email: const {NotificationCategory.asksOfMe}),
          presence: null,
          pushDelivered: true,
          now: now,
        ),
        EmailDecision.immediate,
      );
    });

    test('present user with delivered push gets no immediate email', () {
      expect(
        gate.decideEmail(
          category: NotificationCategory.asksOfMe,
          prefs: prefs(email: const {NotificationCategory.asksOfMe}),
          presence: presentUser,
          pushDelivered: true,
          now: now,
        ),
        EmailDecision.none,
      );
    });

    test('non-asksOfMe never immediate; digests when cadence on', () {
      expect(
        gate.decideEmail(
          category: NotificationCategory.coordination,
          prefs: prefs(
            email: const {NotificationCategory.coordination},
            digest: DigestCadence.daily,
          ),
          presence: null,
          pushDelivered: false,
          now: now,
        ),
        EmailDecision.digest,
      );
    });

    test('quiet hours defers an otherwise-immediate email to digest', () {
      expect(
        gate.decideEmail(
          category: NotificationCategory.asksOfMe,
          prefs: prefs(
            email: const {NotificationCategory.asksOfMe},
            quietStart: 11 * 60,
            quietEnd: 13 * 60,
            digest: DigestCadence.daily,
          ),
          presence: null,
          pushDelivered: false,
          now: now,
        ),
        EmailDecision.digest,
      );
    });

    test('snooze suppresses email entirely', () {
      expect(
        gate.decideEmail(
          category: NotificationCategory.asksOfMe,
          prefs: prefs(
            email: const {NotificationCategory.asksOfMe},
            snoozeUntil: now.add(const Duration(hours: 2)),
            digest: DigestCadence.daily,
          ),
          presence: null,
          pushDelivered: false,
          now: now,
        ),
        EmailDecision.none,
      );
    });
  });

  group('defaults', () {
    test('conservative email opt-in (asksOfMe only) and ambient push off', () {
      final p = NotificationPreferencesEntity.defaults('a1');
      expect(
        p.emailCategories,
        {
          NotificationCategory.asksOfMe,
          NotificationCategory.connections,
        },
      );
      expect(p.pushCategories.contains(NotificationCategory.ambient), isFalse);
      expect(p.pushCategories.contains(NotificationCategory.asksOfMe), isTrue);
      expect(p.emailDigest, DigestCadence.off);
    });
  });
}
