// #660: the invitation accept dialog names the inviter by the name the
// viewer sees (Profile.shownName), so the server placeholder «New member»
// reads «Новый участник» in Russian, in the name line and in the signup body.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/display_name_prompt.dart';
import 'package:tentura/features/invitation/domain/entity/invite_preview.dart';
import 'package:tentura/features/invitation/ui/dialog/invitation_accept_dialog.dart';
import 'package:tentura/ui/l10n/l10n.dart';

const _beacon = InvitePreviewBeacon(id: 'B1', title: 'Перевезти диван');
const _ru = Locale('ru');

Future<void> _pump(
  WidgetTester tester,
  Profile profile, {
  required bool signup,
}) => tester.pumpWidget(
  MaterialApp(
    locale: _ru,
    theme: TenturaTheme.light(),
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(
      body: InvitationAcceptDialog(
        profile: profile,
        beacon: _beacon,
        signup: signup,
      ),
    ),
  ),
);

void main() {
  final l10n = lookupL10n(_ru);
  setUp(() {
    setNewMemberDisplayNameLabel(l10n.newMemberDisplayName);
    addTearDown(() => setNewMemberDisplayNameLabel(kNewMemberDisplayName));
  });

  for (final (description, profile, shownName, hiddenName) in const [
    (
      'the placeholder name is translated to Russian',
      Profile(id: 'U1', displayName: 'New member'),
      'Новый участник',
      'New member',
    ),
    (
      'the contact name takes precedence over the stored name',
      Profile(id: 'U1', displayName: 'Oleg', contactName: 'Аня'),
      'Аня',
      'Oleg',
    ),
    (
      'the stored name is shown when there is no contact name',
      Profile(id: 'U1', displayName: 'Олег Петров'),
      'Олег Петров',
      null,
    ),
  ]) {
    for (final signup in [false, true]) {
      testWidgets(
        '$description for ${signup ? 'new users' : 'existing accounts'}',
        (tester) async {
          await _pump(tester, profile, signup: signup);

          expect(find.text(shownName), findsOneWidget);
          expect(
            find.textContaining('свяжет вас с $shownName'),
            signup ? findsOneWidget : findsNothing,
          );
          if (!signup) {
            expect(
              find.text(l10n.inviteAcceptBeaconAccessBody),
              findsOneWidget,
            );
          }
          if (hiddenName != null) {
            expect(find.textContaining(hiddenName), findsNothing);
          }
        },
      );
    }
  }
}
