import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

void main() {
  final enArb =
      jsonDecode(File('l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
  final ruArb =
      jsonDecode(File('l10n/app_ru.arb').readAsStringSync())
          as Map<String, dynamic>;

  const availabilityKeys = [
    'availabilityLimitedTitle',
    'availabilityPausedUntil',
    'availabilitySelfOpen',
    'availabilitySelfLimited',
    'availabilitySelfPausedUntil',
    'availabilitySelfThenLimited',
    'availabilityResumeEcho',
    'availabilityPersonPaused',
    'availabilityUnaffectedNote',
    'availabilityResumeNow',
    'availabilityDeliveredPartial',
    'availabilityDeliveredPartialMany',
    'availabilitySheetTitle',
    'availabilityLimitedSwitchTitle',
    'availabilityLimitedSwitchDescription',
    'availabilityPauseSectionTitle',
    'availabilityPauseSectionDescription',
    'availabilityPresetTomorrow',
    'availabilityPresetThisWeekend',
    'availabilityPresetOneWeek',
    'availabilityPresetOneMonth',
    'availabilityPresetPickDate',
    'availabilityPauseAction',
    'availabilityChangeAction',
    'availabilityDatePickerTitle',
  ];

  test('availability ARB keys exist in EN and RU with metadata', () {
    for (final key in availabilityKeys) {
      expect(enArb[key], isNotNull, reason: 'app_en.arb missing $key');
      expect(ruArb[key], isNotNull, reason: 'app_ru.arb missing $key');
      expect(enArb['@$key'], isNotNull, reason: 'app_en.arb missing @$key');
      expect(ruArb['@$key'], isNotNull, reason: 'app_ru.arb missing @$key');
    }
  });

  test('availability EN/RU copy matches architecture §10 and unit contracts', () {
    final en = L10nEn();
    final ru = L10nRu();

    expect(en.availabilityLimitedTitle, 'Only important requests');
    expect(ru.availabilityLimitedTitle, 'Только важные запросы');

    expect(
      en.availabilityPausedUntil('Mon'),
      'Not taking new requests until Mon',
    );
    expect(
      ru.availabilityPausedUntil('пн'),
      'Не принимает новые запросы до пн',
    );

    expect(en.availabilitySelfOpen, 'Open to requests');
    expect(ru.availabilitySelfOpen, 'Вы принимаете запросы');

    expect(en.availabilitySelfLimited, 'Only important requests');
    expect(ru.availabilitySelfLimited, 'Вы принимаете только важные запросы');

    expect(
      en.availabilitySelfPausedUntil('Tue'),
      'Not taking new requests · until Tue',
    );
    expect(
      ru.availabilitySelfPausedUntil('вт'),
      'Вы не принимаете новые запросы · до вт',
    );

    expect(en.availabilitySelfThenLimited, 'Then: only important requests');
    expect(ru.availabilitySelfThenLimited, 'Затем: только важные запросы');

    expect(
      en.availabilityResumeEcho('Wed'),
      "You'll receive requests again on Wed",
    );
    expect(
      ru.availabilityResumeEcho('ср'),
      'Вы снова начнёте получать запросы ср',
    );

    expect(
      en.availabilityPersonPaused('Ada', 'Thu'),
      "Ada isn't taking new requests until Thu.",
    );
    expect(
      ru.availabilityPersonPaused('Ada', 'чт'),
      'Ada не принимает новые запросы до чт.',
    );

    expect(
      en.availabilityUnaffectedNote,
      "Requests and chats you're already in aren't affected.",
    );
    expect(
      ru.availabilityUnaffectedNote,
      'Уже начатые запросы и чаты это не затрагивает.',
    );

    expect(en.availabilityResumeNow, 'Resume now');
    expect(ru.availabilityResumeNow, 'Возобновить сейчас');

    expect(
      en.availabilityDeliveredPartial(2, 3, 'Bob'),
      "Delivered to 2 of 3 — Bob isn't taking new requests right now.",
    );
    expect(
      ru.availabilityDeliveredPartial(2, 3, 'Bob'),
      'Отправлено 2 из 3 — Bob сейчас не принимает новые запросы.',
    );

    expect(
      en.availabilityDeliveredPartialMany(1, 4, 3),
      "Delivered to 1 of 4 — 3 people aren't taking new requests right now.",
    );
    expect(
      ru.availabilityDeliveredPartialMany(1, 4, 3),
      'Отправлено 1 из 4 — 3 получателей сейчас не принимают новые запросы.',
    );

    expect(en.availabilitySheetTitle, 'Request availability');
    expect(ru.availabilitySheetTitle, 'Приём запросов');

    expect(en.availabilityPauseAction, 'Pause');
    expect(ru.availabilityPauseAction, 'Приостановить');

    expect(en.availabilityChangeAction, 'Change');
    expect(ru.availabilityChangeAction, 'Изменить');

    expect(en.availabilityDatePickerTitle, 'Resume on');
    expect(ru.availabilityDatePickerTitle, 'Возобновить');
  });

  test('availability EN values use Request/Chat terminology', () {
    for (final key in availabilityKeys) {
      final value = enArb[key] as String;
      expect(
        RegExp(r'\b[Bb]eacon\b|\bbeacons\b|\bBeacons\b').hasMatch(value),
        isFalse,
        reason: '$key must not use beacon',
      );
      expect(
        RegExp(r'\b[Rr]oom\b').hasMatch(value),
        isFalse,
        reason: '$key must not use room',
      );
      if (key.contains('Delivered') ||
          key.contains('Unaffected') ||
          key.contains('PauseSection')) {
        expect(
          value.toLowerCase(),
          anyOf(contains('request'), contains('chat')),
          reason: '$key should mention requests or chats',
        );
      }
    }
  });

  test('Russian self strings use second person; others use third person', () {
    final ru = L10nRu();
    for (final text in [
      ru.availabilitySelfOpen,
      ru.availabilitySelfLimited,
      ru.availabilitySelfPausedUntil('пн'),
      ru.availabilityResumeEcho('пн'),
    ]) {
      expect(text.toLowerCase(), anyOf(contains('вы'), contains('вас')));
    }
    expect(
      ru.availabilityPausedUntil('пн').toLowerCase(),
      isNot(RegExp(r'\bвы\b')),
    );
    expect(
      ru.availabilityPersonPaused('Ada', 'пн').toLowerCase(),
      isNot(RegExp(r'\bвы\b')),
    );
  });

  test('Russian availability copy avoids gendered predicative adjectives', () {
    final ru = L10nRu();
    final banned = RegExp(
      r'\b(открыт|открыта|открыто|закрыт|закрыта|закрыто|недоступен|недоступна|недоступно)\b',
      caseSensitive: false,
    );
    for (final key in availabilityKeys) {
      final value = ruArb[key] as String;
      expect(banned.hasMatch(value), isFalse, reason: 'app_ru.arb $key');
    }
    for (final text in [
      ru.availabilitySelfOpen,
      ru.availabilitySelfLimited,
      ru.availabilitySelfPausedUntil('пн'),
      ru.availabilityPausedUntil('пн'),
      ru.availabilityPersonPaused('Ada', 'пн'),
    ]) {
      expect(banned.hasMatch(text), isFalse, reason: text);
    }
  });
}
