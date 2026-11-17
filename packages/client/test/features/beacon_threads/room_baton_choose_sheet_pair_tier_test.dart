// «Who'll take it?» choose sheet: a confirmed pair is listed under the PAIR's
// tier (the server's min of both members), not under the tier of whichever
// member the row happens to be keyed on. 375x667, EN and RU.

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../support/phone_surface.dart';

const _a = 'Alex Anders';
const _x = 'Xenia Partner';
const _s = 'Sam Solo';
const _pickForMe = 'Pick for me';

RoomBatonCandidate _c(
  String id,
  String title,
  int tier, {
  RoomBatonTaker? partner,
}) => RoomBatonCandidate(
  userId: id,
  title: title,
  tier: tier,
  response: RoomBatonResponse.canHelp,
  partner: partner,
);

/// A (tier 2) and X (tier 1) confirmed each other: the pair's tier is 1.
final _mutualMixedTiers = RoomBatonAuthorData(
  id: 'baton-1',
  status: RoomBatonStatus.collecting,
  candidates: [
    _c('u-a', _a, 2, partner: const RoomBatonTaker(id: 'u-x', title: _x)),
    _c('u-x', _x, 1, partner: const RoomBatonTaker(id: 'u-a', title: _a)),
    _c('u-s', _s, 2),
  ],
  allAnswered: false,
  eligibleCount: 3,
  pairs: const [RoomBatonConfirmedPair(takerId: 'u-a', partnerId: 'u-x', tier: 1)],
);

final _soloOnly = RoomBatonAuthorData(
  id: 'baton-1',
  status: RoomBatonStatus.collecting,
  candidates: [_c('u-a', _a, 1), _c('u-s', _s, 2)],
  allAnswered: false,
  eligibleCount: 2,
);

Widget _app(RoomBatonData baton, Locale locale, List<String?> picks) =>
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: locale,
      home: MediaQuery(
        data: const MediaQueryData(size: kPhoneSurface),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: SingleChildScrollView(
              child: RoomBatonCard(
                baton: baton,
                onSelect: picks.add,
                onCancel: () {},
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _openSheet(
  WidgetTester tester,
  RoomBatonData baton,
  Locale locale,
  List<String?> picks,
  String chooseLabel,
) async {
  await usePhoneSurface(tester);
  await tester.pumpWidget(_app(baton, locale, picks));
  await tester.pumpAndSettle();
  await tester.tap(find.text(chooseLabel));
  await tester.pump(kDoubleTapTimeout);
  await tester.pumpAndSettle();
}

/// The open sheet's list (the card behind it repeats names and tiers).
Finder _sheet() => find.ancestor(
  of: find.byIcon(Icons.casino_outlined),
  matching: find.byType(ListView),
);

Finder _inSheet(String text) =>
    find.descendant(of: _sheet(), matching: find.text(text));

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(_inSheet(text)).dy;

void main() {
  group('Choose sheet groups a confirmed pair under the pair tier', () {
    testWidgets('EN: pair of tier 2 + tier 1 members sits under Priority 1, '
        'solo helper under Priority 2', (tester) async {
      final picks = <String?>[];
      await _openSheet(
        tester,
        _mutualMixedTiers,
        const Locale('en'),
        picks,
        'Choose now',
      );

      const pair = '$_a and $_x';
      expect(_inSheet(pair), findsOneWidget);
      expect(_inSheet('together'), findsOneWidget);
      expect(_inSheet(_x), findsNothing, reason: 'no separate partner row');
      expect(_inSheet('Priority 1'), findsOneWidget);
      expect(_inSheet('Priority 2'), findsOneWidget);
      expect(_top(tester, 'Priority 1'), lessThan(_top(tester, pair)));
      expect(_top(tester, pair), lessThan(_top(tester, 'Priority 2')));
      expect(_top(tester, 'Priority 2'), lessThan(_top(tester, _s)));
      expect(tester.takeException(), isNull);

      await tester.tap(_inSheet(pair));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(picks, ['u-a']);
    });

    testWidgets('RU: the same pair sits under «Приоритет 1» without overflow', (
      tester,
    ) async {
      await _openSheet(
        tester,
        _mutualMixedTiers,
        const Locale('ru'),
        <String?>[],
        'Выбрать сейчас',
      );

      const pair = '$_a и $_x';
      expect(_inSheet(pair), findsOneWidget);
      expect(_inSheet('вместе'), findsOneWidget);
      expect(_inSheet('Приоритет 1'), findsOneWidget);
      expect(_inSheet('Приоритет 2'), findsOneWidget);
      expect(_top(tester, 'Приоритет 1'), lessThan(_top(tester, pair)));
      expect(_top(tester, pair), lessThan(_top(tester, 'Приоритет 2')));
      expect(_top(tester, 'Приоритет 2'), lessThan(_top(tester, _s)));
      expect(tester.takeException(), isNull);
    });
  });

  group('Choose sheet with solo helpers only', () {
    testWidgets('keeps each helper under their own tier and Pick for me '
        'first, calling onSelect(null)', (tester) async {
      final picks = <String?>[];
      await _openSheet(tester, _soloOnly, const Locale('en'), picks, 'Choose now');

      expect(_top(tester, 'Pick for me'), lessThan(_top(tester, 'Priority 1')));
      expect(_top(tester, 'Priority 1'), lessThan(_top(tester, _a)));
      expect(_top(tester, _a), lessThan(_top(tester, 'Priority 2')));
      expect(_top(tester, 'Priority 2'), lessThan(_top(tester, _s)));

      await tester.tap(_inSheet(_pickForMe));
      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(picks, [null]);
    });
  });
}
