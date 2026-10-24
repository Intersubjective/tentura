// Issue #677: English request counts ignored plurals ("Show 1 requests",
// "1 active requests forwarded to them"), and the Russian tooltips read
// "1 активных запросов". Counts of 1/2/5 must agree in both locales.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/ui/l10n/l10n_en.dart';
import 'package:tentura/ui/l10n/l10n_ru.dart';

void main() {
  final en = L10nEn();
  final ru = L10nRu();

  group('English request counts', () {
    test('Field person panel: Show N requests', () {
      expect(en.constellationPersonShowRequests(1), 'Show 1 request');
      expect(en.constellationPersonShowRequests(2), 'Show 2 requests');
    });

    test('People card: forwarded to them', () {
      expect(
        en.friendContextInboxCount(1),
        '1 active request forwarded to them',
      );
      expect(
        en.friendContextInboxCount(2),
        '2 active requests forwarded to them',
      );
    });

    test('People card: you both see', () {
      expect(en.friendContextSharedCount(1), '1 active request you both see');
      expect(en.friendContextSharedCount(2), '2 active requests you both see');
    });
  });

  group('Russian request counts', () {
    test('guard: Field person panel keeps the count in parentheses', () {
      expect(ru.constellationPersonShowRequests(1), 'Показать запросы (1)');
      expect(ru.constellationPersonShowRequests(5), 'Показать запросы (5)');
    });

    test('People card: forwarded to them', () {
      expect(
        ru.friendContextInboxCount(1),
        '1 активный запрос переслан ему/ей',
      );
      expect(
        ru.friendContextInboxCount(2),
        '2 активных запроса переслано ему/ей',
      );
      expect(
        ru.friendContextInboxCount(5),
        '5 активных запросов переслано ему/ей',
      );
      expect(
        ru.friendContextInboxCount(21),
        '21 активный запрос переслан ему/ей',
      );
    });

    test('People card: you both see', () {
      expect(ru.friendContextSharedCount(1), '1 активный запрос видите оба');
      expect(ru.friendContextSharedCount(2), '2 активных запроса видите оба');
      expect(ru.friendContextSharedCount(5), '5 активных запросов видите оба');
    });
  });
}
