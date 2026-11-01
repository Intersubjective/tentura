// #258 QA round 1: a disabled «Read all» / «Dismiss all» was
// pixel-identical to the enabled one, because TenturaTextAction gave its
// label a fixed colour, so TextButton's disabled foreground never applied.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_app_bar.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _cases = [
  (Locale('ru'), Size(375, 667), 'RU 375×667'),
  (Locale('en'), Size(1280, 800), 'EN desktop'),
];

Future<void> _pump(
  WidgetTester tester, {
  required Locale locale,
  required Size size,
  required Widget Function(BuildContext context, L10n l10n) child,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: MediaQuery(
        data: MediaQueryData(size: size),
        child: TenturaResponsiveScope(
          child: Scaffold(
            body: Builder(
              builder: (context) => child(context, L10n.of(context)!),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Color? _labelColor(WidgetTester tester, String label) =>
    tester.widget<Text>(find.text(label)).style?.color;

void main() {
  for (final (locale, size, name) in _cases) {
    final l10n = lookupL10n(locale);

    for (final label in [l10n.updatesMarkAllSeen, l10n.inboxDismissAll]) {
      testWidgets('$name: disabled «$label» does not look enabled', (
        tester,
      ) async {
        await _pump(
          tester,
          locale: locale,
          size: size,
          child: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TenturaTextAction(label: label, onPressed: () {}),
              TenturaTextAction(
                label: label,
                semanticsIdentifier: 'disabled',
              ),
            ],
          ),
        );
        final colors = tester
            .widgetList<Text>(find.text(label))
            .map((t) => t.style?.color)
            .toList();
        expect(colors, hasLength(2));
        expect(colors[0], isNotNull);
        expect(colors[1], isNotNull);
        expect(colors[1], isNot(colors[0]));
        expect(colors[1], tester.element(find.text(label).first).tt.textFaint);
      });
    }

    for (final hasUnread in [true, false]) {
      testWidgets('$name: Updates bar «Read all» colour follows enablement '
          '(${hasUnread ? 'enabled' : 'disabled'})', (tester) async {
        await _pump(
          tester,
          locale: locale,
          size: size,
          child: (context, l10n) => UpdatesFeedAppBarRow(
            title: l10n.notificationHistoryTitle,
            markAllLabel: l10n.updatesMarkAllSeen,
            hasUnread: hasUnread,
            onMarkAll: () {},
            showSearchIcon: context.windowClass == WindowClass.compact,
            searchOpen: false,
            onSearchPressed: () {},
            searchTooltip: l10n.updatesSearchHint,
          ),
        );
        final tt = tester.element(find.byType(UpdatesFeedAppBarRow)).tt;
        expect(
          _labelColor(tester, l10n.updatesMarkAllSeen),
          hasUnread ? tt.info : tt.textFaint,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
