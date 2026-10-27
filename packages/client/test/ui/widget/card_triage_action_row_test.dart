import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
                  secondaryTooltip: 'Remove from Activity',
                  onSecondary: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final offer = tester.getCenter(
      find.byKey(TestIds.key(TestIds.inboxOfferHelp)),
    );
    final forward = tester.getCenter(
      find.byKey(TestIds.key(TestIds.inboxForward)),
    );
    final dismiss = tester.getCenter(
      find.byKey(TestIds.key(TestIds.inboxDismiss)),
    );

    expect(offer.dy, lessThan(forward.dy));
    expect((forward.dy - dismiss.dy).abs(), lessThan(4));
    expect(dismiss.dx, greaterThan(forward.dx));
  });

  Future<void> pumpIconOnlyDismiss(
    WidgetTester tester, {
    String? tooltip,
  }) async {
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
                  secondaryTooltip: tooltip,
                  onSecondary: () async {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  SemanticsNode dismissNode() => find.semantics
      .byPredicate(
        (n) => n.getSemanticsData().identifier == TestIds.inboxDismiss,
      )
      .evaluate()
      .single;

  testWidgets('an icon-only dismiss without a tooltip still has a name', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpIconOnlyDismiss(tester);

    expect(dismissNode(), isSemantics(label: 'Dismiss', isButton: true));
    handle.dispose();
  });

  testWidgets('an icon-only dismiss keeps its tooltip as its name (guard)', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpIconOnlyDismiss(tester, tooltip: 'Remove from Activity');

    expect(
      dismissNode(),
      isSemantics(label: 'Remove from Activity', isButton: true),
    );
    handle.dispose();
  });

  testWidgets('the icon-only dismiss is at least a 48dp target', (
    tester,
  ) async {
    await pumpIconOnlyDismiss(tester, tooltip: 'Remove from Activity');

    final size = tester.getSize(find.byKey(TestIds.key(TestIds.inboxDismiss)));
    expect(size.width, greaterThanOrEqualTo(kMinInteractiveDimension));
    expect(size.height, greaterThanOrEqualTo(kMinInteractiveDimension));
  });
}
