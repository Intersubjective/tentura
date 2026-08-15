import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/profile_app_bar_title.dart';

void main() {
  Future<void> pumpTitle(WidgetTester tester, Profile profile) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        theme: TenturaTheme.light(),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: ProfileAppBarTitle(profile: profile)),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows nickname then canonical secondary', (tester) async {
    await pumpTitle(
      tester,
      const Profile(
        id: 'U-peer',
        contactName: 'Mom',
        displayName: 'Alice',
        handle: 'alice',
      ),
    );

    expect(find.text('Mom'), findsOneWidget);
    expect(find.text('Alice · @alice'), findsOneWidget);
  });

  testWidgets('empty shownName uses noName with handle secondary', (
    tester,
  ) async {
    await pumpTitle(
      tester,
      const Profile(id: 'U-peer', handle: 'alice'),
    );

    expect(find.text('No name'), findsOneWidget);
    expect(find.text('@alice'), findsOneWidget);
  });

  testWidgets('blocked profile still shows canonical secondary', (
    tester,
  ) async {
    await pumpTitle(
      tester,
      const Profile(
        id: 'U-blocked',
        displayName: 'Blocked Person',
        handle: 'blocked',
      ),
    );

    expect(find.text('Blocked Person'), findsOneWidget);
    expect(find.text('@blocked'), findsOneWidget);
  });
}
