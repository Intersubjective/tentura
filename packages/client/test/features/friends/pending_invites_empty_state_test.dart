import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/friends/ui/widget/pending_invites_empty_state.dart';
import 'package:tentura/ui/l10n/l10n.dart';

void main() {
  Future<void> pump(
    WidgetTester tester, {
    required Locale locale,
    required VoidCallback onCreateInvitation,
  }) => tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      theme: TenturaTheme.light(),
      home: Scaffold(
        // #661 review: the widget reads L10n from its context.
        body: PendingInvitesEmptyState(onCreateInvitation: onCreateInvitation),
      ),
    ),
  );

  testWidgets('empty Pending list says there are no pending invitations', (
    tester,
  ) async {
    await pump(tester, locale: const Locale('en'), onCreateInvitation: () {});

    expect(find.text('No pending invitations'), findsOneWidget);
    expect(
      find.text('Create an invitation to bring in someone you trust.'),
      findsOneWidget,
    );
    expect(find.text('Create invitation'), findsOneWidget);
  });

  testWidgets(
    'empty Pending list does not talk about a link that is not shown',
    (
      tester,
    ) async {
      final en = lookupL10n(const Locale('en'));
      await pump(tester, locale: const Locale('en'), onCreateInvitation: () {});

      expect(find.text(en.invitationDualPurposeBody), findsNothing);
      expect(find.text(en.friendsInvitesEmptyTitle), findsNothing);
      expect(find.textContaining('link'), findsNothing);
    },
  );

  testWidgets('Create invitation button triggers the callback', (
    tester,
  ) async {
    var taps = 0;
    await pump(
      tester,
      locale: const Locale('en'),
      onCreateInvitation: () => taps++,
    );

    await tester.tap(find.text('Create invitation'));
    await tester.pump();

    expect(taps, 1);
  });

  testWidgets('Russian copy is translated and has no link sentence', (
    tester,
  ) async {
    final ru = lookupL10n(const Locale('ru'));
    await pump(tester, locale: const Locale('ru'), onCreateInvitation: () {});

    expect(find.text('Нет ожидающих приглашений'), findsOneWidget);
    expect(find.text(ru.invitationDualPurposeBody), findsNothing);
    expect(find.textContaining('Ссылка'), findsNothing);
  });
}
