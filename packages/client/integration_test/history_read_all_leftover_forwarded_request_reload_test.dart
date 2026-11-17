// Real browser, real local stack. A Request the viewer follows (never opened)
// has an old forward receipt an earlier «Read all» left seen-but-uncleared,
// behind more than one page (50) of other unread History items. «Read all» then a cold app
// relaunch (the app is booted again in the same page; the companion guarantee
// of a brand-new browser document is Playwright's) must leave the forwarded
// item and every other History item read, and the badge without a count.
// Run with the local server's Request-creation cap raised (the test creates 53
// Requests): BEACON_CREATE_MAX_PER_USER=500 ./scripts/run_client_integration_web_local.sh ...
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/domain/attention/entity/attention_feed.dart';
import 'package:tentura/domain/attention/port/attention_repository_port.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_accept.req.gql.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_create.req.gql.dart';
import 'package:tentura/features/settings/ui/bloc/settings_cubit.dart';
import 'package:tentura/features/updates/ui/widget/updates_feed_tile.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/test_ids.dart';

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
    'Read all over a long History clears the old followed forwarded Request '
    'too: no unread badge digit and a read tile after the app is booted '
    'again in the same page',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);
      final people = await bootstrapWitnessFixture(
        runId: uniqueRunId('history-read-all-leftover'),
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
      for (var i = 0; i < 52; i++) {
        final more = await createPublishedBeacon(
          title: uniqueRequestTitle('History bulk Request $i'),
        );
        await forwardBeaconTo(beaconId: more, recipientId: people.bobUserId);
      }
      // Forwarded last, so its tile is on History's first page (the paging
      // of a leftover beyond page one is the server and cubit tests').
      final id = await createPublishedBeacon(
        title: uniqueRequestTitle('History followed Request'),
      );
      await forwardBeaconTo(beaconId: id, recipientId: people.bobUserId);
      await logout(tester);
      await loginAs(tester, people.bobEmail);
      await GetIt.I<SettingsCubit>().setLocalePreference('en');
      await pumpBounded(tester, frames: 12);

      // The state an older Read all left: followed, receipt read, not cleared.
      await GetIt.I<InboxRepository>().setStatus(
        beaconId: id,
        status: InboxItemStatus.watching,
      );
      final attention = GetIt.I<AttentionRepositoryPort>();
      String? cursor;
      final oldReceipts = <String>[];
      do {
        final feed = await attention.fetch(
          view: AttentionView.all,
          cursor: cursor,
        );
        oldReceipts.addAll([
          for (final r in feed.page.items)
            if (r.beaconId == id) r.id,
        ]);
        cursor = feed.page.nextCursor;
      } while (cursor != null);
      expect(oldReceipts, isNotEmpty, reason: 'precondition: forward receipt');
      await attention.markSeen(oldReceipts);

      await _openHistory(tester);
      expect(
        (await attention.fetch(view: AttentionView.unread)).summary.unreadTotal,
        greaterThan(50),
        reason: 'precondition: more than one page of unread items',
      );
      expect(_unreadBadge, findsWidgets, reason: 'precondition: badge count');

      await tester.tap(find.text('Read all'));
      await pumpUntil(
        tester,
        () => !finderHasMatch(find.byKey(UpdatesFeedTile.unreadDotKey)),
        label: 'no unread marker after Read all',
      );
      // The badge follows the summary the Read all refresh brings back.
      await pumpUntil(
        tester,
        () => !finderHasMatch(_unreadBadge),
        label: 'no unread badge count after Read all',
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
        (await GetIt.I<AttentionRepositoryPort>().fetch(
          view: AttentionView.unread,
        )).summary.unreadTotal,
        0,
        reason: 'server count after the restart',
      );
      final tile = find.bySemanticsIdentifier(
        TestIds.updatesReceipt(oldReceipts.first),
      );
      await pumpUntil(
        tester,
        () => finderHasMatch(tile),
        label: 'the followed Request tile is listed',
      );
      expect(
        tile,
        findsOneWidget,
        reason: 'the followed Request is listed',
      );
      expect(
        find.descendant(
          of: tile,
          matching: find.byKey(UpdatesFeedTile.unreadDotKey),
        ),
        findsNothing,
        reason: 'the followed Request tile renders as read',
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
