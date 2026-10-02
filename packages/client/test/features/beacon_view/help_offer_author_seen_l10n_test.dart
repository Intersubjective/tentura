// Issue #178 part 2: the offerer's author-seen copy must come from l10n
// (English and Russian ARB entries), not hardcoded English in the widget.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'help_offer_author_seen_test_support.dart';

const _notSeenEnglish = 'Sent · not seen by the author yet';
const _seenEnglish = 'Seen by the author · awaiting decision';

Map<String, dynamic> _arb(String locale) =>
    jsonDecode(File('l10n/app_$locale.arb').readAsStringSync())
        as Map<String, dynamic>;

/// The single message key whose English value is exactly [value].
String? _enKeyFor(String value) {
  final keys = _arb('en').entries
      .where((e) => !e.key.startsWith('@') && e.value == value)
      .map((e) => e.key)
      .toList();
  return keys.length == 1 ? keys.single : null;
}

void main() {
  testWidgets('the pending-offer label renders in Russian from l10n', (
    tester,
  ) async {
    final key = _enKeyFor(_notSeenEnglish);
    expect(key, isNotNull, reason: 'app_en.arb needs "$_notSeenEnglish"');
    final ruLabel = _arb('ru')[key] as String?;
    expect(ruLabel, isNotNull, reason: 'app_ru.arb must translate $key');

    final h = (await tester.runAsync(() async {
      final h = AuthorSeenHarness();
      await h.load();
      return h;
    }))!;
    await pumpPeople(tester, h.cubit.state, locale: const Locale('ru'));

    expect(find.text(ruLabel!), findsOneWidget);
    expect(find.text(_notSeenEnglish), findsNothing);

    await tester.runAsync(h.dispose);
  });

  testWidgets('the seen pending-offer label renders in Russian from l10n', (
    tester,
  ) async {
    final key = _enKeyFor(_seenEnglish);
    expect(key, isNotNull, reason: 'app_en.arb needs "$_seenEnglish"');
    final ruLabel = _arb('ru')[key] as String?;
    expect(ruLabel, isNotNull, reason: 'app_ru.arb must translate $key');

    final h = (await tester.runAsync(() async {
      final h = AuthorSeenHarness(
        rows: [
          offerRow(
            authorSeenAt: kOfferCreatedAt.add(const Duration(minutes: 5)),
          ),
        ],
      );
      await h.load();
      return h;
    }))!;
    await pumpPeople(tester, h.cubit.state, locale: const Locale('ru'));

    expect(find.text(ruLabel!), findsOneWidget);
    expect(find.text(_seenEnglish), findsNothing);
    await tester.runAsync(h.dispose);
  });
}
