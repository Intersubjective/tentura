import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_responsive_scope.dart';
import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_baton_data.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_baton_card.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _viewer = Profile(id: 'u-viewer', displayName: 'Viewer Self');
const _author = Profile(id: 'u-anna', displayName: 'Anna Author');

Widget _app(RoomBatonCandidateData baton, Locale locale) => MaterialApp(
  theme: TenturaTheme.light(),
  localizationsDelegates: L10n.localizationsDelegates,
  supportedLocales: L10n.supportedLocales,
  locale: locale,
  home: MediaQuery(
    data: const MediaQueryData(size: Size(400, 900)),
    child: TenturaResponsiveScope(
      child: Scaffold(
        body: SingleChildScrollView(
          // togetherEnabled deliberately not passed: released default.
          child: RoomBatonCard(
            baton: baton,
            viewerUserId: _viewer.id,
            batonAuthorUserId: _author.id,
          ),
        ),
      ),
    ),
  ),
);

const _collecting = RoomBatonCandidateData(
  id: 'baton-1',
  status: RoomBatonStatus.collecting,
  myResponse: RoomBatonResponse.waiting,
);

const _taken = RoomBatonCandidateData(
  id: 'baton-1',
  status: RoomBatonStatus.taken,
  myResponse: RoomBatonResponse.waiting,
  outcome: RoomBatonOutcome.someoneElse,
);

void main() {
  group('Released default of the together action', () {
    test('the feature flag is on', () {
      expect(kBatonTogetherEnabled, isTrue);
    });

    for (final (locale, text) in [
      (const Locale('en'), 'Together with…'),
      (const Locale('ru'), 'Вместе с кем-то…'),
    ]) {
      testWidgets(
        'collecting candidate card offers the together action by default '
        '(${locale.languageCode})',
        (tester) async {
          await tester.pumpWidget(_app(_collecting, locale));
          await tester.pumpAndSettle();
          expect(find.text(text), findsOneWidget);
        },
      );

      testWidgets(
        'no together action once the baton is no longer collecting '
        '(${locale.languageCode})',
        (tester) async {
          await tester.pumpWidget(_app(_taken, locale));
          await tester.pumpAndSettle();
          // Positive control: the card rendered its outcome line.
          expect(
            find.textContaining(
              locale.languageCode == 'en'
                  ? 'Someone else was selected'
                  : 'Выбрали другого человека',
            ),
            findsOneWidget,
          );
          expect(find.text(text), findsNothing);
        },
      );
    }
  });
}
