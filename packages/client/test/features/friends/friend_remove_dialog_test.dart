// #463: the stop-trusting confirmation still said "delete … from friends
// list" after #84 moved the app to one-way trust wording. The dialog must
// also reach assistive tech: an alert dialog route named by its question,
// with both actions as buttons.

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_theme.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/friends/ui/dialog/friend_remove_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// The engine-visible node that scopes and names the dialog route.
List<SemanticsData> _routeNodes() => find.semantics
    .byPredicate((node) {
      final flags = node.getSemanticsData().flagsCollection;
      return !node.isMergedIntoParent && flags.scopesRoute && flags.namesRoute;
    })
    .evaluate()
    .map((node) => node.getSemanticsData())
    .toList();

/// Engine-visible button nodes, by label.
List<String> _buttonLabels() => find.semantics
    .byPredicate(
      (node) =>
          !node.isMergedIntoParent &&
          node.getSemanticsData().flagsCollection.isButton,
    )
    .evaluate()
    .map((node) => node.getSemanticsData().label)
    .toList();

Future<void> _openDialog(WidgetTester tester, String locale) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: TenturaTheme.light(),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      locale: Locale(locale),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => FriendRemoveDialog.show(
              context,
              profile: const Profile(id: 'U1', displayName: 'Vadim'),
              onRemove: () async {},
            ),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  for (final (locale, title, confirm, cancel) in [
    ('en', 'Stop trusting Vadim?', 'Stop trusting', 'Cancel'),
    (
      'ru',
      'Перестать доверять пользователю Vadim?',
      'Перестать доверять',
      'Отмена',
    ),
  ]) {
    testWidgets('the dialog is an alert dialog route named by its question '
        '($locale)', (tester) async {
      final semantics = tester.ensureSemantics();
      await _openDialog(tester, locale);

      expect(
        find.semantics.byPredicate(
          (node) => node.getSemanticsData().role == SemanticsRole.alertDialog,
        ),
        findsOneWidget,
      );
      final routes = _routeNodes();
      expect(routes, hasLength(1));
      expect(routes.single.label, title);
      semantics.dispose();
    });

    testWidgets('both actions are buttons for screen readers ($locale)', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await _openDialog(tester, locale);

      expect(_buttonLabels(), containsAll(<String>[confirm, cancel]));
      semantics.dispose();
    });
  }

  for (final (locale, title, confirm) in [
    ('en', 'Stop trusting Vadim?', 'Stop trusting'),
    ('ru', 'Перестать доверять пользователю Vadim?', 'Перестать доверять'),
  ]) {
    testWidgets('asks to stop trusting ($locale)', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: TenturaTheme.light(),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          locale: Locale(locale),
          home: Scaffold(
            body: FriendRemoveDialog(
              profile: const Profile(id: 'U1', displayName: 'Vadim'),
              onRemove: () async {},
            ),
          ),
        ),
      );

      expect(find.text(title), findsOneWidget);
      expect(find.widgetWithText(TextButton, confirm), findsOneWidget);
    });
  }
}
