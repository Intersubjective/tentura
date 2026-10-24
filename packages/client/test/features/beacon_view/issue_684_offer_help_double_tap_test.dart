// #684: a double tap (or double click) on the offer sheet's «Offer help»
// must send one offer and leave the user on the Request page. Both taps can
// reach Flutter before the next frame (a fast double click on the web); the
// second one then hit the closing sheet's button again and popped the page
// under it (QA on 7.50.3: back on the Requests list, URL still on the
// request).

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/dialog/help_offer_message_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

const _requestsList = 'Requests list';
const _requestPage = 'Request page';

Future<List<HelpOfferDialogOutcome?>> _pumpRequestPageWithSheet(
  WidgetTester tester, {
  required Size size,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final outcomes = <HelpOfferDialogOutcome?>[];
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      builder: (context, child) => TenturaResponsiveScope(child: child!),
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    body: Column(
                      children: [
                        const Text(_requestPage),
                        TextButton(
                          onPressed: () async => outcomes.add(
                            await HelpOfferMessageDialog.show(
                              context,
                              title: 'Offer help',
                              hintText: 'Your message',
                              showHelpTypeChips: true,
                            ),
                          ),
                          child: const Text('open'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              child: const Text(_requestsList),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_requestsList));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  await tester.enterText(
    find.byKey(TestIds.key(TestIds.helpOfferMessage)),
    'I can help',
  );
  await tester.pumpAndSettle();
  return outcomes;
}

void main() {
  for (final (name, size) in [
    ('desktop dialog', const Size(1280, 800)),
    ('phone sheet', const Size(390, 844)),
  ]) {
    testWidgets('$name: one tap on Offer help closes only the sheet', (
      tester,
    ) async {
      final outcomes = await _pumpRequestPageWithSheet(tester, size: size);

      await tester.tap(find.byKey(TestIds.key(TestIds.helpOfferSubmit)));
      await tester.pumpAndSettle();

      expect(find.byType(HelpOfferMessageDialog), findsNothing);
      expect(outcomes, hasLength(1));
      expect(outcomes.single?.message, 'I can help');
      expect(find.text(_requestPage), findsOneWidget);
      expect(find.text(_requestsList), findsNothing);
    });

    testWidgets(
      '$name: a double tap on Offer help keeps the Request page on top',
      (tester) async {
        final outcomes = await _pumpRequestPageWithSheet(tester, size: size);

        // Both taps land inside kDoubleTapTimeout and before the next frame,
        // as a fast double click does in the browser.
        final submit = tester.getCenter(
          find.byKey(TestIds.key(TestIds.helpOfferSubmit)),
        );
        await tester.tapAt(submit);
        await tester.tapAt(submit);
        await tester.pump(kDoubleTapTimeout ~/ 2);
        await tester.tapAt(submit);
        await tester.pumpAndSettle();

        expect(find.byType(HelpOfferMessageDialog), findsNothing);
        expect(outcomes, hasLength(1), reason: 'one offer is sent');
        expect(
          find.text(_requestPage),
          findsOneWidget,
          reason: 'exactly one pop: the Request page is still on top',
        );
        expect(find.text(_requestsList), findsNothing);
      },
    );
  }
}
