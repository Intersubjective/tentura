import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../../support/phone_surface.dart';

/// Long enough to exceed [ShowMoreText]'s default three-line trim at 375 px.
final _longBio = List.filled(40, 'Описание профиля').join(' ');

Widget _harness({
  required Locale locale,
  required Widget child,
}) {
  return MaterialApp(
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    locale: locale,
    home: TenturaResponsiveScope(
      child: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

Finder _descriptionText() => find.descendant(
  of: find.byType(ShowMoreText),
  matching: find.byWidgetPredicate(
    (w) => w is Text && w.textSpan != null,
  ),
);

void _tapTrimLink(WidgetTester tester, String label) {
  TapGestureRecognizer? recognizer;
  tester.widget<Text>(_descriptionText()).textSpan!.visitChildren((span) {
    if (span is TextSpan &&
        span.text == label &&
        span.recognizer is TapGestureRecognizer) {
      recognizer = span.recognizer! as TapGestureRecognizer;
      return false;
    }
    return true;
  });
  expect(recognizer, isNotNull, reason: 'no "$label" link');
  recognizer!.onTap!();
}

void main() {
  testWidgets('375×667 RU: collapsed and expanded trim links are localised', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final l10nRu = lookupL10n(const Locale('ru'));

    await tester.pumpWidget(
      _harness(
        locale: const Locale('ru'),
        child: ShowMoreText(_longBio),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('read more'), findsNothing);
    expect(find.textContaining(l10nRu.beaconShowcaseReadMore), findsOneWidget);

    _tapTrimLink(tester, l10nRu.beaconShowcaseReadMore);
    await tester.pumpAndSettle();

    expect(find.text('show less'), findsNothing);
    expect(find.textContaining(l10nRu.beaconShowcaseShowLess), findsOneWidget);
  });

  testWidgets('375×667 EN: collapsed and expanded trim links are localised', (
    tester,
  ) async {
    await usePhoneSurface(tester);
    final l10nEn = lookupL10n(const Locale('en'));

    await tester.pumpWidget(
      _harness(
        locale: const Locale('en'),
        child: ShowMoreText(_longBio),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining(l10nEn.beaconShowcaseReadMore), findsOneWidget);
    expect(find.text('read more'), findsNothing);

    _tapTrimLink(tester, l10nEn.beaconShowcaseReadMore);
    await tester.pumpAndSettle();

    expect(find.textContaining(l10nEn.beaconShowcaseShowLess), findsOneWidget);
    expect(find.text('show less'), findsNothing);
  });
}
