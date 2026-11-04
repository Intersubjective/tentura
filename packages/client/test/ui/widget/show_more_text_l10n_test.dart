import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

import '../../support/phone_surface.dart';

/// Long enough to exceed [ShowMoreText]'s default three-line trim at 375 px.
final _longBio = List.filled(40, 'Описание профиля').join(' ');

final _longBioEndingWithPeriod =
    '${List.filled(40, 'Profile text').join(' ')}.';

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

String? _trimLinkSpanText(WidgetTester tester) {
  String? linkText;
  tester.widget<Text>(_descriptionText()).textSpan!.visitChildren((span) {
    if (span is TextSpan &&
        span.recognizer is TapGestureRecognizer &&
        span.text != null &&
        span.text!.isNotEmpty &&
        !span.text!.startsWith('\u2026')) {
      linkText = span.text;
    }
    return true;
  });
  return linkText;
}

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

List<String> _collectSpanTexts(InlineSpan? span) {
  if (span == null) {
    return [];
  }
  if (span is TextSpan) {
    final text = span.text;
    final children = span.children ?? const <InlineSpan>[];
    return [
      if (text != null && text.isNotEmpty) text,
      ...children.expand(_collectSpanTexts),
    ];
  }
  return [];
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
    expect(_trimLinkSpanText(tester), l10nRu.beaconShowcaseReadMore);

    _tapTrimLink(tester, l10nRu.beaconShowcaseReadMore);
    await tester.pumpAndSettle();

    expect(find.text('show less'), findsNothing);
    final expandedLink = ShowMoreText.formatExpandedTrimText(
      l10nRu.beaconShowcaseShowLess,
    );
    expect(_trimLinkSpanText(tester), expandedLink);
    expect(
      expandedLink,
      startsWith('\u00A0'),
      reason: 'expanded link needs a leading separator',
    );
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
    expect(_trimLinkSpanText(tester), l10nEn.beaconShowcaseReadMore);

    _tapTrimLink(tester, l10nEn.beaconShowcaseReadMore);
    await tester.pumpAndSettle();

    final expandedLink = ShowMoreText.formatExpandedTrimText(
      l10nEn.beaconShowcaseShowLess,
    );
    expect(_trimLinkSpanText(tester), expandedLink);
    expect(find.text('show less'), findsNothing);
  });

  testWidgets('320 wide EN: expanded "Show less" stays on one line', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final l10nEn = lookupL10n(const Locale('en'));

    await tester.pumpWidget(
      _harness(
        locale: const Locale('en'),
        child: ShowMoreText(_longBioEndingWithPeriod),
      ),
    );
    await tester.pumpAndSettle();

    _tapTrimLink(tester, l10nEn.beaconShowcaseReadMore);
    await tester.pumpAndSettle();

    final spanTexts = _collectSpanTexts(
      tester.widget<Text>(_descriptionText()).textSpan,
    );
    expect(spanTexts, isNot(contains('Show')));
    expect(spanTexts, isNot(contains('less')));
    expect(
      spanTexts,
      contains(
        ShowMoreText.formatExpandedTrimText(l10nEn.beaconShowcaseShowLess),
      ),
    );
  });

  testWidgets('375×667 RU: collapsed delimiter before read-more is unchanged', (
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

    final spanTexts = _collectSpanTexts(
      tester.widget<Text>(_descriptionText()).textSpan,
    );
    expect(spanTexts, contains('\u2026 '));
    expect(spanTexts, contains(l10nRu.beaconShowcaseReadMore));
  });

  testWidgets('320 wide EN: bio ending with period keeps expanded separator', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 667));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final l10nEn = lookupL10n(const Locale('en'));

    await tester.pumpWidget(
      _harness(
        locale: const Locale('en'),
        child: ShowMoreText(_longBioEndingWithPeriod),
      ),
    );
    await tester.pumpAndSettle();

    _tapTrimLink(tester, l10nEn.beaconShowcaseReadMore);
    await tester.pumpAndSettle();

    final expandedLink = ShowMoreText.formatExpandedTrimText(
      l10nEn.beaconShowcaseShowLess,
    );
    expect(_trimLinkSpanText(tester), expandedLink);
  });
}
