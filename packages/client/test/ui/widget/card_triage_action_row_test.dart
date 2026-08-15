import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/widget/card_triage_action_row.dart';

void main() {
  testWidgets('omits Forward button when onForward is null', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: CardTriageActionRow(
              onForward: null,
              onOfferHelp: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(TestIds.key(TestIds.inboxForward)), findsNothing);
    expect(find.byKey(TestIds.key(TestIds.inboxOfferHelp)), findsOneWidget);
  });

  testWidgets('shows Forward button when onForward is set', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            width: 400,
            child: CardTriageActionRow(
              onForward: () {},
              onOfferHelp: () async {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(TestIds.key(TestIds.inboxForward)), findsOneWidget);
  });

  testWidgets('compact layout puts dismiss on the Forward row', (tester) async {
    const viewport = Size(375, 812);
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(size: viewport),
          child: TenturaResponsiveScope(
            child: Scaffold(
              body: SizedBox(
                width: viewport.width,
                child: CardTriageActionRow(
                  onForward: () {},
                  onOfferHelp: () async {},
                  secondaryIcon: Icons.close,
                  secondaryTooltip: 'Remove from inbox',
                  onSecondary: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final offer = tester.getCenter(find.byKey(TestIds.key(TestIds.inboxOfferHelp)));
    final forward = tester.getCenter(find.byKey(TestIds.key(TestIds.inboxForward)));
    final dismiss = tester.getCenter(find.byKey(TestIds.key(TestIds.inboxDismiss)));

    expect(offer.dy, lessThan(forward.dy));
    expect((forward.dy - dismiss.dy).abs(), lessThan(4));
    expect(dismiss.dx, greaterThan(forward.dx));
  });
}
