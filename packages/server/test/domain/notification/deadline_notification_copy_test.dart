import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/notification_kind.dart';
import 'package:tentura_server/domain/notification/notification_copy_renderer.dart';
import 'package:tentura_server/domain/notification/notification_identity.dart';

void main() {
  const midnight = '2026-11-28T21:00:00Z';
  const evening = '2026-11-21T15:00:00Z';
  final now = DateTime.utc(2026, 11, 16, 9);

  for (final (
        locale,
        moved,
        timed,
        utc,
        nextYear,
        timedNextYear,
        reminder,
        timedReminder,
      )
      in const [
        (
          'en',
          'Anna moved the deadline to 29 Nov',
          'Anna moved the deadline to 21 Nov, 18:00',
          'Anna moved the deadline to 28 Nov, 21:00',
          'Anna moved the deadline to 5 Jan 2027',
          'Anna moved the deadline to 5 Jan 2027, 18:00',
          'Deadline: 29 Nov',
          'Deadline: 21 Nov, 18:00',
        ),
        (
          'ru',
          'Anna: новый срок — 29 ноября',
          'Anna: новый срок — 21 ноября, 18:00',
          'Anna: новый срок — 28 ноября, 21:00',
          'Anna: новый срок — 5 января 2027',
          'Anna: новый срок — 5 января 2027, 18:00',
          'Срок: 29 ноября',
          'Срок: 21 ноября, 18:00',
        ),
      ]) {
    String sentence(String key, String endAt, {int offset = 180}) =>
        const NotificationCopyRenderer()
            .render(
              presentationKey: key,
              kind: key == 'deadline_changed'
                  ? NotificationKind.deadlineChanged
                  : NotificationKind.deadlineReminder,
              facts: {'newEndAt': endAt},
              identity: const NotificationIdentity(
                entityKind: NotificationEntityKind.request,
                label: 'Fix the roof',
                readable: true,
                tombstone: false,
                actorName: 'Anna',
                actorHidden: false,
                relatedLabel: null,
                expired: false,
              ),
              locale: locale,
              tzOffsetMinutes: offset,
              now: now,
            )
            .sentence;

    group('Deadline notifications ($locale)', () {
      test('a change omits the time only for the recipient at midnight', () {
        expect(sentence('deadline_changed', evening), timed);
        expect(sentence('deadline_changed', midnight, offset: 0), utc);
        expect(sentence('deadline_changed', midnight), moved);
      });

      test('a reminder omits midnight and keeps an evening time', () {
        expect(sentence('deadline_reminder', evening), timedReminder);
        expect(sentence('deadline_reminder', midnight), reminder);
      });

      test(
        'a deadline in another year shows the year with or without a time',
        () {
          expect(
            sentence('deadline_changed', '2027-01-05T15:00:00Z'),
            timedNextYear,
          );
          expect(
            sentence('deadline_changed', '2027-01-04T21:00:00Z'),
            nextYear,
          );
        },
      );
    });
  }
}
