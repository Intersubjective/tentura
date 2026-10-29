import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/attention/attention_case.dart';
import 'package:tentura/features/beacon_lobby/data/gql/_g/beacon_lobby.req.gql.dart';
import 'package:tentura/features/beacon_lobby/ui/screen/beacon_lobby_screen.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_entry_row.dart';
import 'package:tentura/features/beacon_threads/data/gql/_g/room_message_create.req.gql.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/forward/data/gql/_g/forward_beacon.req.gql.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_accept.req.gql.dart';
import 'package:tentura/features/invitation/data/gql/_g/invitation_create.req.gql.dart';
import 'package:tentura/main.dart' as app;

import 'e2e_test_helpers.dart';

/// Separate browser processes make each acceptance stage independently red,
/// while every setup goes through real auth, create, forward, and room APIs.
enum QuestionsUnreadScenario { unreadWithoutNotices, clearOnOpen, afterVisit }

void questionsUnreadJourney(QuestionsUnreadScenario scenario) {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final description = switch (scenario) {
    QuestionsUnreadScenario.unreadWithoutNotices =>
      'author Overview counts unread Questions independently of cleared notices',
    QuestionsUnreadScenario.clearOnOpen =>
      'opening Questions clears the author Overview unread count',
    QuestionsUnreadScenario.afterVisit =>
      'author Overview counts only Questions posted after the last visit',
  };

  testWidgets(description, (tester) async {
    await launchApp(app.main);
    await pumpSettleBounded(tester);
    final people = await bootstrapWitnessFixture(
      runId: uniqueRunId('questions-read-state'),
    );
    await logout(tester);
    await loginAs(tester, people.aliceEmail);
    // The witness fixture deliberately has only Alice's one-way vouch for
    // Bob. Accept a real contact invitation to permit direct Request routing.
    final invitation = await postGraphQlAsUser(
      email: people.aliceEmail,
      restoreEmail: people.aliceEmail,
      request: GInvitationCreateReq((b) => b.vars.addresseeName = 'Bob'),
    );
    final inviteId =
        ((invitation['data'] as Map)['invitationCreate'] as Map)['id']
            as String;
    final accepted = await postGraphQlAsUser(
      email: people.bobEmail,
      restoreEmail: people.aliceEmail,
      request: GInvitationAcceptReq((b) => b.vars.id = inviteId),
    );
    expect((accepted['data'] as Map)['invitationAccept'], isNotNull);
    final id = await createPublishedBeacon(
      title: uniqueRequestTitle('Questions read state'),
    );
    addTearDown(() => deleteBeaconById(id));
    await forwardBeaconTo(beaconId: id, recipientId: people.bobUserId);
    final forwarded = await postGraphQlAsUser(
      email: people.bobEmail,
      restoreEmail: people.aliceEmail,
      request: GForwardBeaconReq(
        (b) => b.vars
          ..beaconId = id
          ..recipientIds.add(people.carolUserId),
      ),
    );
    expect(
      ((forwarded['data'] as Map)['beaconForward']
          as Map)['deliveredRecipientIds'],
      contains(people.carolUserId),
      reason: "Bob actually forwards Alice's Request to Carol.",
    );
    expect(
      await fetchForwardEdgePairs(
        beaconId: id,
        // Bob can inspect both his received and his sent edge. The author
        // does not get another person's outgoing edges through Hasura.
        asEmail: people.bobEmail,
        restoreEmail: people.aliceEmail,
      ),
      containsAll([
        '${people.aliceUserId}->${people.bobUserId}',
        '${people.bobUserId}->${people.carolUserId}',
      ]),
    );

    final entry = find.byKey(BeaconLobbyEntryRow.entryKey);
    Finder count(String text) => find.descendant(
      of: entry,
      matching: find.text(text),
    );
    Finder newCounts() => find.descendant(
      of: entry,
      matching: find.textContaining(RegExp(r'^\d+ new$')),
    );
    Future<void> overview() async {
      await goToDeepLink(tester, '$kPathBeaconView/$id');
      await pumpUntilVisible(tester, entry);
    }

    await overview();
    // No Questions have ever been opened or posted by anyone. This is the
    // no-unread fallback before any visit, rather than only after opening.
    expect(count('No questions yet'), findsOneWidget);
    expect(newCounts(), findsNothing);

    // Bob creates the Questions scope, then both addressed readers post
    // via the production mutations. Alice has never opened that scope.
    final opened = await postGraphQlAsUser(
      email: people.bobEmail,
      restoreEmail: people.aliceEmail,
      request: GBeaconLobbyReq((b) => b.vars.beaconId = id),
    );
    final lobbyId =
        ((opened['data'] as Map)['BeaconLobby'] as Map)['lobbyId'] as String;
    Future<void> post(String email, String body) async {
      final result = await postGraphQlAsUser(
        email: email,
        restoreEmail: people.aliceEmail,
        request: GRoomMessageCreateReq(
          (b) => b.vars
            ..beaconId = id
            ..threadItemId = lobbyId
            ..body = body,
        ),
      );
      expect(
        ((result['data'] as Map)['RoomMessageCreate'] as Map)['id'],
        isNotEmpty,
      );
    }

    Future<void> clearNotices() async {
      // Clearing attention is a separate user action from reading Questions.
      // Use production APIs and prove there is no countable notice remaining.
      final attention = GetIt.I<AttentionCase>();
      final page = await attention.activityAttention(beaconId: id);
      for (final receipt in page.events) {
        if (receipt.coordinationItemId != lobbyId) continue;
        if (receipt.isLiveObligation) {
          await attention.settleReceipt(receipt.id);
        } else if (!receipt.isCleared) {
          await attention.clearReceipt(receiptId: receipt.id);
        }
      }
      final cleared = await attention.activityAttention(beaconId: id);
      expect(
        cleared.events.where(
          (r) =>
              r.coordinationItemId == lobbyId &&
              r.settledAt == null &&
              !r.isCleared,
        ),
        isEmpty,
      );
      await pumpSettleBounded(tester);
    }

    await post(people.bobEmail, 'How many boxes?');
    await post(people.carolEmail, 'Which Saturday?');
    await pumpSettleBounded(tester);

    if (scenario == QuestionsUnreadScenario.unreadWithoutNotices) {
      await clearNotices();
      // A fresh production page load also rules out counting only messages
      // that arrived while an Overview widget happened to be mounted.
      await goToDeepLink(tester, '/');
      await overview();
      await pumpUntil(
        tester,
        () => count('2 new').evaluate().isNotEmpty,
        label: 'two unread Questions with no active attention notices',
      );
      expect(count('2 new'), findsOneWidget);
      expect(count('2 messages'), findsNothing);
      return;
    }

    if (scenario == QuestionsUnreadScenario.afterVisit) {
      await clearNotices();
    }
    // Every journey that opens Questions must first establish the visible
    // unread state, including the journey with attention already cleared.
    await pumpUntil(
      tester,
      () => count('2 new').evaluate().isNotEmpty,
      label: 'two unread Questions before opening',
    );
    expect(count('2 new'), findsOneWidget);
    expect(count('2 messages'), findsNothing);
    await tester.ensureVisible(entry);
    await tapAndSettle(tester, entry);
    await pumpUntilVisible(tester, find.byType(BeaconLobbyScreen));
    await pumpUntil(
      tester,
      () => find.byType(RoomMessageTile).evaluate().length == 2,
      label: 'Bob and Carol questions in the shared chat',
    );
    await tapAndSettle(tester, find.byType(BeaconLobbyBackButton));
    await pumpUntilVisible(tester, entry);
    // Assert on return, before any third message or notice manipulation.
    expect(count('2 messages'), findsOneWidget);
    expect(
      newCounts(),
      findsNothing,
      reason: "Opening Questions advances Alice's Questions read cursor.",
    );

    if (scenario == QuestionsUnreadScenario.afterVisit) {
      await post(people.bobEmail, 'Is there parking?');
      await clearNotices();
      // Only the actual server room-message hint may update the mounted
      // Overview. No refresh, fake hint, seeded receipt, or navigation here.
      await pumpUntil(
        tester,
        () => count('1 new').evaluate().isNotEmpty,
        label: "one question after Alice's last Questions visit",
      );
      expect(count('1 new'), findsOneWidget);
      expect(count('3 messages'), findsNothing);
      expect(count('3 new'), findsNothing);
    }
  });
}
