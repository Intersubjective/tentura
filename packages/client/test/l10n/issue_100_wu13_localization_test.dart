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
    expect(en.profileVisibilityYouCanSee('Ada'), 'Ada is in your trust network');
    expect(ru.profileVisibilityYouCanSee('Ada'), 'Пользователь Ada — в вашей сети доверия');
    expect(
      en.profileVisibilityCantSeeYou('Ada'),
      "You aren't in Ada's trust network yet",
    );
    expect(
      ru.profileVisibilityCantSeeYou('Ada'),
      'Вас пока нет в сети доверия пользователя Ada',
    );
    expect(en.profileVisibilityTheyCanSeeYou('Ada'), "You're in Ada's trust network");
    expect(ru.profileVisibilityTheyCanSeeYou('Ada'), 'Вы — в сети доверия пользователя Ada');
    expect(
      en.profileVisibilityYouDontSeeThem('Ada'),
      "Ada isn't in your trust network yet",
    );
    expect(
      ru.profileVisibilityYouDontSeeThem('Ada'),
      'Пользователя Ada пока нет в вашей сети доверия',
    );
    expect(en.profileVisibilityNeither, 'No two-way visibility');
    expect(ru.profileVisibilityNeither, 'Нет двусторонней видимости');
    expect(
      en.profileRequestUnavailable,
      'They don’t see you yet, so you can’t send them Requests.',
    );
    expect(
      ru.profileRequestUnavailable,
      'Вас пока не видят, поэтому отправлять запросы нельзя.',
    );
    expect(en.profileRequestOptions, 'Request options');
    expect(ru.profileRequestOptions, 'Варианты отправки запроса');
    expect(en.graphShowMoreConnections(5), 'Show 5 more connections');
    expect(ru.graphShowMoreConnections(5), 'Показать ещё связей: 5');
  });

  // #100 + #261: per direction (each of you trusts the other), trust either
  // direct or through people you trust — in plain words, without the
  // "MeritRank" name a newcomer cannot read.
  test(
    'legend eye copy describes trust per direction, direct or through others',
    () {
      final en = L10nEn();
      final ru = L10nRu();

      for (final text in [
        en.graphLegendEyeOpen,
        en.graphLegendForwardEligible,
      ]) {
        expect(text.toLowerCase(), contains('each of you trusts the other'));
        expect(text.toLowerCase(), contains('directly or through'));
        expect(text.toLowerCase(), isNot(contains('meritrank')));
        expect(text.toLowerCase(), isNot(contains('both ways')));
      }
      for (final text in [
        ru.graphLegendEyeOpen,
        ru.graphLegendForwardEligible,
      ]) {
        expect(text, contains('каждый доверяет другому'));
        expect(text, contains('напрямую или через'));
        expect(text.toLowerCase(), isNot(contains('meritrank')));
        expect(text, isNot(contains('в обе стороны')));
      }
    },
  );
}
