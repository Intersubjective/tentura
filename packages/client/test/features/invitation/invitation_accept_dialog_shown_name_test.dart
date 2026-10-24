// #660: the invitation accept dialog names the inviter by the name the
// viewer sees (Profile.shownName), so the server placeholder «New member»
// reads «Новый участник» in Russian, in the name line and in the body.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/display_name_prompt.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_accept_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _beacon = InvitePreviewBeacon(id: 'B1', title: 'Перевезти диван');

Future<void> _pump(WidgetTester tester, Profile profile) => tester.pumpWidget(
  MaterialApp(
    locale: const Locale('ru'),
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: InvitationAcceptDialog(profile: profile, beacon: _beacon),
    ),
  ),
);

void main() {
  testWidgets('a New member inviter reads Новый участник in Russian', (
    tester,
  ) async {
    setNewMemberDisplayNameLabel(
      lookupL10n(const Locale('ru')).newMemberDisplayName,
    );
    addTearDown(() => setNewMemberDisplayNameLabel(kNewMemberDisplayName));
    await _pump(tester, const Profile(id: 'U1', displayName: 'New member'));

    expect(find.text('Новый участник'), findsOneWidget);
    expect(
      find.textContaining('свяжет вас с Новый участник'),
      findsOneWidget,
    );
    expect(find.textContaining('New member'), findsNothing);
  });

  testWidgets('a contact name wins over the stored name', (tester) async {
    await _pump(
      tester,
      const Profile(id: 'U1', displayName: 'Oleg', contactName: 'Аня'),
    );

    expect(find.text('Аня'), findsOneWidget);
    expect(find.textContaining('свяжет вас с Аня'), findsOneWidget);
    expect(find.textContaining('Oleg'), findsNothing);
  });

  testWidgets('guard: a chosen name without a contact name is unchanged', (
    tester,
  ) async {
    await _pump(tester, const Profile(id: 'U1', displayName: 'Олег Петров'));

    expect(find.text('Олег Петров'), findsOneWidget);
    expect(find.textContaining('свяжет вас с Олег Петров'), findsOneWidget);
  });
}
