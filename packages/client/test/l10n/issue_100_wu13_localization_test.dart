import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

void main() {
  final enArb =
      jsonDecode(
            File('l10n/app_en.arb').readAsStringSync(),
          )
          as Map<String, dynamic>;
  final ruArb =
      jsonDecode(
            File('l10n/app_ru.arb').readAsStringSync(),
          )
          as Map<String, dynamic>;

  const wu13Keys = [
    'friendsPeopleGraph',
    'friendsPeopleMore',
    'friendsBlockedPeople',
    'graphBack',
    'graphCenterView',
    'graphResetGenealogyOrigin',
    'trustThisUser',
    'profileVisibilityMutual',
    'profileVisibilityYouCanSee',
    'profileVisibilityCantSeeYou',
    'profileVisibilityTheyCanSeeYou',
    'profileVisibilityYouDontSeeThem',
    'profileVisibilityNeither',
    'profileRequestUnavailable',
    'profileRequestOptions',
    'graphShowMoreConnections',
    'graphLegendEyeOpen',
    'graphLegendForwardEligible',
  ];

  test('WU13 ARB keys exist in EN and RU with metadata', () {
    for (final key in wu13Keys) {
      expect(enArb[key], isNotNull, reason: 'app_en.arb missing $key');
      expect(ruArb[key], isNotNull, reason: 'app_ru.arb missing $key');
      expect(enArb['@$key'], isNotNull, reason: 'app_en.arb missing @$key');
      expect(ruArb['@$key'], isNotNull, reason: 'app_ru.arb missing @$key');
    }
  });

  test('WU13 EN/RU copy matches plan semantics', () {
    final en = L10nEn();
    final ru = L10nRu();

    expect(en.friendsPeopleGraph, 'Graph');
    expect(ru.friendsPeopleGraph, 'Граф');
    expect(en.friendsPeopleMore, 'More');
    expect(ru.friendsPeopleMore, 'Ещё');
    expect(en.friendsBlockedPeople, 'Blocked people');
    expect(ru.friendsBlockedPeople, 'Заблокированные');
    expect(en.graphBack, 'Previous focus');
    expect(ru.graphBack, 'Предыдущий фокус');
    expect(en.graphCenterView, 'Center view');
    expect(ru.graphCenterView, 'Центрировать');
    expect(en.graphResetGenealogyOrigin, 'Reset to origin');
    expect(ru.graphResetGenealogyOrigin, 'Вернуться к началу');
    expect(en.trustThisUser, 'Trust this user');
    expect(ru.trustThisUser, 'Доверять этому пользователю');
    expect(en.profileVisibilityMutual, 'Two-way visibility');
    expect(ru.profileVisibilityMutual, 'Двусторонняя видимость');
    expect(en.profileVisibilityYouCanSee('Ada'), 'You can see Ada');
    expect(ru.profileVisibilityYouCanSee('Ada'), 'Вы видите Ada');
    expect(
      en.profileVisibilityCantSeeYou('Ada'),
      "Ada can't see you yet",
    );
    expect(
      ru.profileVisibilityCantSeeYou('Ada'),
      'Ada пока не видит вас',
    );
    expect(en.profileVisibilityTheyCanSeeYou('Ada'), 'Ada can see you');
    expect(ru.profileVisibilityTheyCanSeeYou('Ada'), 'Ada видит вас');
    expect(
      en.profileVisibilityYouDontSeeThem('Ada'),
      "You don't currently see Ada",
    );
    expect(
      ru.profileVisibilityYouDontSeeThem('Ada'),
      'Сейчас вы не видите Ada',
    );
    expect(en.profileVisibilityNeither, 'No two-way visibility');
    expect(ru.profileVisibilityNeither, 'Нет двусторонней видимости');
    expect(en.profileRequestUnavailable, 'Request unavailable');
    expect(ru.profileRequestUnavailable, 'Запрос недоступен');
    expect(en.profileRequestOptions, 'Request options');
    expect(ru.profileRequestOptions, 'Варианты отправки запроса');
    expect(en.graphShowMoreConnections(5), 'Show 5 more connections');
    expect(ru.graphShowMoreConnections(5), 'Показать ещё связей: 5');
  });

  test(
    'legend eye copy describes Trust or MeritRank per direction, not MR both ways',
    () {
      final en = L10nEn();
      final ru = L10nRu();

      for (final text in [
        en.graphLegendEyeOpen,
        en.graphLegendForwardEligible,
      ]) {
        expect(text.toLowerCase(), contains('trust'));
        expect(text.toLowerCase(), contains('meritrank'));
        expect(text.toLowerCase(), isNot(contains('both ways')));
      }
      for (final text in [
        ru.graphLegendEyeOpen,
        ru.graphLegendForwardEligible,
      ]) {
        expect(text.toLowerCase(), contains('meritrank'));
        expect(text, isNot(contains('в обе стороны')));
        expect(text, isNot(contains('положительный meritrank')));
      }
    },
  );
}
