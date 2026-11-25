import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

void main() {
  final year = DateTime.now().year;
  final midnight = DateTime(year, 11, 29);
  final evening = DateTime(year, 11, 21, 18);

  for (final (l10n, named, generic, timed, reminder, timedReminder) in [
    (
      L10nEn(),
      'Anna moved the deadline to 29 Nov',
      'Deadline moved to 29 Nov',
      'Anna moved the deadline to 21 Nov, 18:00',
      'Deadline: 29 Nov',
      'Deadline: 21 Nov, 18:00',
    ),
    (
      L10nRu(),
      'Anna: новый срок — 29 ноября',
      'Новый срок — 29 ноября',
      'Anna: новый срок — 21 ноября, 18:00',
      'Срок: 29 ноября',
      'Срок: 21 ноября, 18:00',
    ),
  ]) {
    String headline(String key, DateTime deadline, {String? actorName}) =>
        resolveUpdatesFeedRowCopy(
          title: 'Deadline changed',
          body: '',
          presentationKey: key,
          presentationPayloadJson: jsonEncode({
            'newEndAt': deadline.toUtc().toIso8601String(),
            'actorName': ?actorName,
          }),
          l10n: l10n,
        ).headline;

    group(
      'Deadline headlines in Notification history (${l10n.localeName})',
      () {
        test('a named change omits midnight and keeps an evening time', () {
          expect(
            headline('deadline_changed', evening, actorName: 'Anna'),
            timed,
          );
          expect(
            headline('deadline_changed', midnight, actorName: 'Anna'),
            named,
          );
        });

        test('a change without an actor still shows the date', () {
          expect(headline('deadline_changed', midnight), generic);
        });

        test('a reminder omits midnight and keeps an evening time', () {
          expect(headline('deadline_reminder', evening), timedReminder);
          expect(headline('deadline_reminder', midnight), reminder);
        });
      },
    );
  }
}
