// Real browser, real local stack. A Request forwarded to the viewer and never
// opened is unread in notification History. «Read all» then a cold app
// restart (the app is booted again in the same page; the companion guarantee
// of a brand-new browser document is Playwright's) must leave the forwarded
// item and every other History item read, and the badge without a count.
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_accept.req.gql.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_create.req.gql.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

final _unreadBadge = find.descendant(
  of: find.byKey(const ValueKey<String>('updates-unread')),
  matching: find.textContaining(RegExp(r'\d')),
);

Future<void> _openHistory(WidgetTester tester) async {
  await goToPath(tester, kPathInboxHistory);
  await GetIt.I<AttentionCase>().refresh();
  await pumpUntilVisible(tester, find.byType(UpdatesFeedTile));
  await pumpBounded(tester, frames: 20);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Read all in History keeps the forwarded Request item and the badge read '
    'after the app restarts',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);
      final people = await bootstrapWitnessFixture(
        runId: uniqueRunId('history-read-all-forward'),
      );
      await logout(tester);
      await loginAs(tester, people.aliceEmail);
      // The fixture has only a one-way Alice -> Bob vouch; a normal contact
      // invitation makes them mutually visible so Alice can forward to Bob.
      final invitation = await postGraphQlAsUser(
        email: people.aliceEmail,
        restoreEmail: people.aliceEmail,
        request: GInvitationCreateReq((b) => b.vars.addresseeName = 'Bob'),
      );
      final invitationId =
          ((invitation['data'] as Map)['invitationCreate'] as Map)['id']
              as String;
      await postGraphQlAsUser(
        email: people.bobEmail,
        restoreEmail: people.aliceEmail,
        request: GInvitationAcceptReq((b) => b.vars.id = invitationId),
      );
      final id = await createPublishedBeacon(
        title: uniqueRequestTitle('History forwarded Request'),
      );
      await forwardBeaconTo(beaconId: id, recipientId: people.bobUserId);
      await logout(tester);
      await loginAs(tester, people.bobEmail);
      await GetIt.I<SettingsCubit>().setLocalePreference('en');
      await pumpBounded(tester, frames: 12);

      await _openHistory(tester);
      expect(
        find.byKey(UpdatesFeedTile.unreadDotKey),
        findsWidgets,
        reason: 'precondition: the forwarded item is unread',
      );
      expect(_unreadBadge, findsWidgets, reason: 'precondition: badge count');

      await tester.tap(find.text('Read all'));
      await pumpUntil(
        tester,
        () => !finderHasMatch(find.byKey(UpdatesFeedTile.unreadDotKey)),
        label: 'no unread marker after Read all',
      );
      expect(_unreadBadge, findsNothing);

      // Reload: boot the app again; the session survives, the screen is
      // rebuilt from the server.
      await launchApp(app.main);
      await pumpSettleBounded(tester);
      if (GetIt.I<AuthCubit>().state.currentAccountId.isEmpty) {
        await loginAs(tester, people.bobEmail);
      }
      await _openHistory(tester);

      expect(
        find.byType(UpdatesFeedTile),
        findsWidgets,
        reason: 'the forwarded item is still listed',
      );
      expect(
        find.byKey(UpdatesFeedTile.unreadDotKey),
        findsNothing,
        reason: 'no History item is unread after the reload',
      );
      expect(_unreadBadge, findsNothing, reason: 'badge shows no count');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
