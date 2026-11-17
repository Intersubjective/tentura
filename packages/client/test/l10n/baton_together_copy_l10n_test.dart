// «Who'll take it?» baton together copy: every key of the plan's copy table is
// in both locales with the canonical text, the same placeholders in EN and RU,
// and Russian names stay nominative (no «с {name}»).

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _canon = <String, (String, String)>{
  'batonTogetherAction': ('Together with…', 'Вместе с кем-то…'),
  'batonTogetherPickTitle': (
    'Who will you take it with?',
    'С кем возьмётесь?',
  ),
  'batonTogetherPending': (
    'Your answer: can help together with {name}. Waiting for {name}.',
    'Ваш ответ: могу помочь вместе. Ждём ответа: {name}.',
  ),
  'batonTogetherAccepted': (
    'Your answer: can help. Together with you: {name}.',
    'Ваш ответ: могу помочь. Вместе с вами: {name}.',
  ),
  'batonTogetherDeclined': (
    "{name} can't join. Can you help?",
    '{name} не сможет присоединиться. Сможете помочь?',
  ),
  'batonPartnerPrompt': (
    '{name} wants to take this on together with you.',
    '{name} предлагает взяться за это вместе с вами.',
  ),
  'batonPartnerJoin': ('Join', 'Возьмусь вместе'),
  'batonPartnerCant': ("Can't", 'Не смогу'),
  'batonPartnerJoined': (
    "You'll take it together with {name}. You can change your mind while it's open.",
    'Вы согласились взяться вместе. Вместе с вами: {name}. Пока выбор не сделан, это можно изменить.',
  ),
  'batonPartnerCantAfterAll': ("Can't after all", 'Всё-таки не смогу'),
  'batonPartnerNote': (
    'This is not taking it yet: the author chooses who takes it.',
    'Это ещё не значит, что вы взялись: выбирает автор.',
  ),
  'batonPartnerReplaceConfirm': (
    'This replaces taking it with {name}.',
    'Тогда вы больше не берётесь вместе с другим человеком: {name}.',
  ),
  'batonStatusCanHelpTogether': ('can help together', 'могут вместе'),
  'batonPairNames': ('{a} and {b}', '{a} и {b}'),
  'batonChoosePairHint': ('together', 'вместе'),
  'batonTookItPair': (
    '{a} and {b} took it.',
    'Берут на себя: {a} и {b}',
  ),
  'batonTookItPairAsk': (
    '{a} and {b} took it: {ask}',
    'Берут на себя: {a} и {b} — {ask}',
  ),
  'batonOutcomeYouTogether': (
    'You and {name} took it.',
    'Вы взялись. Вместе с вами: {name}.',
  ),
  'batonPlanStepPromptBodyPair': (
    '{name} takes it on together with them.',
    'Вместе с исполнителем: {name}.',
  ),
  'batonReceiptPartnerAsked': (
    '{author} wants to take it on together with you',
    '{author} предлагает взяться вместе',
  ),
  'batonReceiptPartnerAnsweredAccepted': (
    '{author} will take it on with you',
    '{author} возьмётся вместе с вами',
  ),
  'batonReceiptPartnerAnsweredDeclined': (
    "{author} can't join you. Answer again",
    '{author} не сможет присоединиться. Ответьте ещё раз',
  ),
  'batonReceiptTakenTogether': (
    'You and {name} took it: {excerpt}',
    'Вы и {name} взялись: {excerpt}',
  ),
};

Set<String> _placeholders(String v) =>
    RegExp(r'\{(\w+)\}').allMatches(v).map((m) => m.group(1)!).toSet();

void main() {
  final en =
      jsonDecode(File('l10n/app_en.arb').readAsStringSync())
          as Map<String, dynamic>;
  final ru =
      jsonDecode(File('l10n/app_ru.arb').readAsStringSync())
          as Map<String, dynamic>;

  group('Baton together copy in both locales', () {
    test('every key exists in both locales', () {
      for (final k in _canon.keys) {
        expect(en[k], isA<String>(), reason: 'app_en.arb $k missing');
        expect(ru[k], isA<String>(), reason: 'app_ru.arb $k missing');
      }
    });

    test('every key carries the canonical EN and RU text', () {
      for (final e in _canon.entries) {
        expect(en[e.key], e.value.$1, reason: 'app_en.arb ${e.key}');
        expect(ru[e.key], e.value.$2, reason: 'app_ru.arb ${e.key}');
      }
    });

    test('EN and RU values use the same placeholders', () {
      for (final k in _canon.keys) {
        expect(
          _placeholders(ru[k] as String),
          _placeholders(en[k] as String),
          reason: k,
        );
      }
    });

    test('Russian names stay nominative: no «с {placeholder}»', () {
      for (final k in _canon.keys) {
        expect(RegExp(r'с \{', caseSensitive: false).hasMatch(ru[k] as String),
          isFalse,
          reason: k,
        );
      }
    });

    test('no baton together value uses internal beacon/room nouns', () {
      for (final k in _canon.keys) {
        expect(
          RegExp(r'[Bb]eacon|\b[Rr]oom').hasMatch(en[k] as String),
          isFalse,
          reason: 'en $k',
        );
        expect(
          RegExp('маяк|комнат', caseSensitive: false).hasMatch(ru[k] as String),
          isFalse,
          reason: 'ru $k',
        );
      }
    });
  });
}
