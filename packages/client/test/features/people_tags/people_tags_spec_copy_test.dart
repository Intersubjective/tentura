import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// #699 sections 5 and 14, mapped from proposed keys to the shipped keys.
const _specCopy = <String, Map<String, String>>{
  'en': {
    'peopleTagsScreenTitle': 'People tags',
    'peopleTagsOnlyYouSee': 'Only you see tags',
    'peopleTagsYourTags': 'Your tags',
    'peopleTagsAutomatic': 'Automatic',
    'peopleTagsAddToTag': 'Add to tag…',
    'peopleTagsNewTag': '+ Tag',
    'peopleTagsSuggestionTitle': 'Tag {names}?',
    'peopleTagsSuggestionNotNow': 'Not now',
    'peopleTagsFromParticipants': 'Tag from participants',
    'peopleTagsForwardNote':
        "Each person gets the forward individually. Recipients don't see the tag name.",
    'peopleTagsForwardOutsideTag': 'Outside the tag, could help',
    'peopleTagsTemporary':
        'Temporary: you see each other while “{title}” is open',
    'constellationTidyUp': 'Tidy up',
    'constellationGather': 'Gather',
    'constellationRestoreFavourite': 'Restore favourite',
    'constellationSaveFavourite': 'Save as favourite',
    'constellationLayoutHistory': 'Layout history',
    'constellationAutoTagMutualContact': 'Mutual contact',
    'constellationAutoTagITrust': 'I trust',
    'constellationAutoTagTrustsMe': 'Trusts me',
    'peopleTagsAutoHelpedMe': 'Helped me',
    'peopleTagsAutoIHelped': 'I helped',
    'peopleTagsAutoWorkedTogether': 'Worked together',
    'peopleTagsAutoInvited': 'Invited me / I invited',
    'peopleTagsAutoForwarded': 'Forwarded to each other',
    'peopleTagsAutoNewOnField': 'New',
  },
  'ru': {
    'peopleTagsScreenTitle': 'Теги людей',
    'peopleTagsOnlyYouSee': 'Теги видите только вы',
    'peopleTagsYourTags': 'Ваши теги',
    'peopleTagsAutomatic': 'Автоматически',
    'peopleTagsAddToTag': 'В тег…',
    'peopleTagsNewTag': '+ Тег',
    'peopleTagsSuggestionTitle': '{names} — добавить в тег?',
    'peopleTagsSuggestionNotNow': 'Не сейчас',
    'peopleTagsFromParticipants': 'Тег из участников',
    'peopleTagsForwardNote':
        'Каждый получит пересылку лично. Название тега получатели не видят.',
    'peopleTagsForwardOutsideTag': 'Вне тега, но может помочь',
    'peopleTagsTemporary':
        'Временно: видите друг друга, пока открыт запрос «{title}»',
    'constellationTidyUp': 'Причесать',
    'constellationGather': 'Собрать кучкой',
    'constellationRestoreFavourite': 'Вернуть любимую',
    'constellationSaveFavourite': 'Сохранить как любимую',
    'constellationLayoutHistory': 'История расстановок',
    'constellationAutoTagMutualContact': 'Взаимный контакт',
    'constellationAutoTagITrust': 'Я доверяю',
    'constellationAutoTagTrustsMe': 'Доверяет мне',
    'peopleTagsAutoHelpedMe': 'Помогали мне',
    'peopleTagsAutoIHelped': 'Я помогал',
    'peopleTagsAutoWorkedTogether': 'Вместе в запросах',
    'peopleTagsAutoInvited': 'Пригласил меня / Я пригласил',
    'peopleTagsAutoForwarded': 'Пересылали друг другу',
    'peopleTagsAutoNewOnField': 'Новый',
  },
};

void main() {
  for (final locale in _specCopy.entries) {
    test('${locale.key} People tags matches the complete spec copy table', () {
      final arb =
          jsonDecode(
                File('l10n/app_${locale.key}.arb').readAsStringSync(),
              )
              as Map<String, dynamic>;
      for (final entry in locale.value.entries) {
        expect(arb[entry.key], entry.value, reason: entry.key);
      }
      for (final entry in arb.entries) {
        if (entry.key.startsWith('peopleTags')) {
          expect(
            entry.value.toString().toLowerCase(),
            isNot(contains('метк')),
            reason: entry.key,
          );
        }
      }
      expect(
        arb['constellationResetPositionsBody'],
        isNot(
          anyOf(contains("can't be undone"), contains('Отменить это нельзя')),
        ),
      );
      expect(
        arb['profileEditLabels'],
        locale.key == 'ru' ? 'Изменить метки' : 'Edit labels',
      );
    });
  }
}
