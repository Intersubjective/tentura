// #660: an avatar is named and lettered after the name the viewer sees
// (Profile.shownName), not the raw stored display name.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/display_name_prompt.dart';
import 'package:tentura/ui/l10n/l10n.dart';

Future<void> _pump(WidgetTester tester, Profile profile) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('ru'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: Center(
        child: TenturaAvatar.medium(profile: profile, onTap: () {}),
      ),
    ),
  ),
);

void main() {
  testWidgets('a New member avatar reads Новый участник in Russian', (
    tester,
  ) async {
    setNewMemberDisplayNameLabel(
      lookupL10n(const Locale('ru')).newMemberDisplayName,
    );
    addTearDown(() => setNewMemberDisplayNameLabel(kNewMemberDisplayName));
    final semantics = tester.ensureSemantics();
    await _pump(tester, const Profile(id: 'U1', displayName: 'New member'));

    expect(
      find.bySemanticsLabel('Новый участник, открыть профиль'),
      findsOneWidget,
    );
    expect(find.text('НУ'), findsOneWidget);
    expect(find.text('NM'), findsNothing);
    semantics.dispose();
  });

  testWidgets('a tappable avatar reads the shown name', (tester) async {
    final semantics = tester.ensureSemantics();
    await _pump(
      tester,
      const Profile(id: 'U1', displayName: 'New member', contactName: 'Аня'),
    );

    expect(find.bySemanticsLabel('Аня, открыть профиль'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('New member')), findsNothing);
    semantics.dispose();
  });

  testWidgets('initials come from the shown name', (tester) async {
    await _pump(
      tester,
      const Profile(id: 'U1', displayName: 'New member', contactName: 'Аня'),
    );

    expect(find.text('АН'), findsOneWidget);
    expect(find.text('NM'), findsNothing);
  });

  testWidgets('guard: a chosen name without a contact name is unchanged', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pump(tester, const Profile(id: 'U1', displayName: 'Олег Петров'));

    expect(
      find.bySemanticsLabel('Олег Петров, открыть профиль'),
      findsOneWidget,
    );
    expect(find.text('ОП'), findsOneWidget);
    semantics.dispose();
  });
}
