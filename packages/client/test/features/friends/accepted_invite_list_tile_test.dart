import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/features/friends/ui/widget/accepted_invite_list_tile.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  Future<void> pump(WidgetTester tester, Widget child) => tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(body: child),
    ),
  );

  final acceptedAt = DateTime.now().subtract(const Duration(hours: 2));

  testWidgets('new-account origin shows "joined via this invite" copy', (
    tester,
  ) async {
    final invitation = InvitationEntity(
      id: 'I1',
      invitedId: 'U1',
      invitedName: 'Alex',
      inviteOrigin: 'new_account',
      acceptedAt: acceptedAt,
      createdAt: acceptedAt,
      updatedAt: acceptedAt,
    );

    await pump(
      tester,
      AcceptedInviteListTile(invitation: invitation, l10n: lookupL10n(const Locale('en'))),
    );

    expect(find.text('Alex joined Tentura via this invite'), findsOneWidget);
    expect(find.text('Joined 2h ago'), findsOneWidget);
  });

  testWidgets(
    'existing-account origin shows "became friends" copy, preferring the '
    'private addressee name over the public display name',
    (tester) async {
      final invitation = InvitationEntity(
        id: 'I2',
        invitedId: 'U2',
        invitedName: 'Alexander Public',
        addresseeName: 'Sasha (gym)',
        inviteOrigin: 'existing_account',
        acceptedAt: acceptedAt,
        createdAt: acceptedAt,
        updatedAt: acceptedAt,
      );

      await pump(
        tester,
        AcceptedInviteListTile(invitation: invitation, l10n: lookupL10n(const Locale('en'))),
      );

      expect(
        find.text('You and Sasha (gym) became friends via this invite'),
        findsOneWidget,
      );
    },
  );

  testWidgets('has no edit/delete affordances — nothing to change once accepted', (
    tester,
  ) async {
    final invitation = InvitationEntity(
      id: 'I3',
      invitedId: 'U3',
      invitedName: 'Alex',
      inviteOrigin: 'new_account',
      acceptedAt: acceptedAt,
      createdAt: acceptedAt,
      updatedAt: acceptedAt,
    );

    await pump(
      tester,
      AcceptedInviteListTile(invitation: invitation, l10n: lookupL10n(const Locale('en'))),
    );

    expect(find.byIcon(Icons.edit_outlined), findsNothing);
    expect(find.byIcon(Icons.delete_outline_rounded), findsNothing);
  });

  testWidgets('is disabled and non-tappable when onTap is null (e.g. hidden accepter)', (
    tester,
  ) async {
    final invitation = InvitationEntity(
      id: 'I4',
      invitedId: 'U4',
      inviteOrigin: 'new_account',
      acceptedAt: acceptedAt,
      createdAt: acceptedAt,
      updatedAt: acceptedAt,
    );

    await pump(
      tester,
      AcceptedInviteListTile(invitation: invitation, l10n: lookupL10n(const Locale('en'))),
    );

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.enabled, isFalse);
    expect(tile.onTap, isNull);
  });

  testWidgets('is enabled and forwards tap when onTap is provided', (
    tester,
  ) async {
    var tapped = false;
    final invitation = InvitationEntity(
      id: 'I5',
      invitedId: 'U5',
      invitedName: 'Alex',
      inviteOrigin: 'new_account',
      acceptedAt: acceptedAt,
      createdAt: acceptedAt,
      updatedAt: acceptedAt,
    );

    await pump(
      tester,
      AcceptedInviteListTile(
        invitation: invitation,
        l10n: lookupL10n(const Locale('en')),
        onTap: () => tapped = true,
      ),
    );

    final tile = tester.widget<ListTile>(find.byType(ListTile));
    expect(tile.enabled, isTrue);

    await tester.tap(find.byType(ListTile));
    expect(tapped, isTrue);
  });
}
