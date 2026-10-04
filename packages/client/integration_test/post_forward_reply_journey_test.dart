import 'package:flutter/widgets.dart' show Locale, Text;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/features/inbox/ui/widget/post_attention_row.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

/// `beacon_participant.room_access` of an admitted Post recipient.
const _roomAccessAdmitted = 3;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a Post sent to two people, answered by one, shows the author the reply '
    'and records one forward edge per recipient and the first-response claim',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);

      final fixture = await bootstrapClosureFixture(
        runId: uniqueRunId('post-forward-reply'),
      );
      final aliceEmail = fixture.authorEmail;
      final aliceUserId = fixture.authorUserId;
      final bobEmail = fixture.helperEmails[0];
      final bobUserId = fixture.helperUserIds[0];
      final carolUserId = fixture.helperUserIds[1];
      final postBody = uniqueRequestTitle('IT post forward reply');
      final replyText = uniqueRequestTitle('IT post reply');

      await logout(tester);
      await loginAs(tester, aliceEmail);
      final beaconId = await createPublishedPost(
        body: postBody,
        recipientIds: [bobUserId, carolUserId],
      );

      await runE2eStep('two forward edges leave the author', () async {
        expect(
          await fetchForwardEdgePairs(
            beaconId: beaconId,
            asEmail: aliceEmail,
            restoreEmail: aliceEmail,
          ),
          {'$aliceUserId->$bobUserId', '$aliceUserId->$carolUserId'},
        );
      });

      await runE2eStep('no first-response claim exists before a reply', () async {
        expect(
          await fetchPostFirstResponseUserIds(
            beaconId: beaconId,
            asEmail: aliceEmail,
            restoreEmail: aliceEmail,
          ),
          isEmpty,
        );
      });

      await logout(tester);
      await loginAs(tester, bobEmail);
      await goToDeepLink(tester, '$kPathBeaconView/$beaconId');
      await runE2eStep('recipient replies in the Post conversation', () async {
        expect(
          await fetchParticipantRoomAccess(
            beaconId: beaconId,
            userId: bobUserId,
            asEmail: bobEmail,
            restoreEmail: bobEmail,
          ),
          _roomAccessAdmitted,
        );
        await pumpUntilVisible(
          tester,
          find.byKey(TestIds.key(TestIds.roomMessageInput)),
        );
        // Sending is dropped until the room has loaded its messages.
        await pumpUntilVisible(
          tester,
          find.byWidgetPredicate(
            (w) => w is RoomMessageTile && w.message.body == postBody,
          ),
        );
        await sendRoomMessage(tester, replyText);
      });

      await runE2eStep('the replying recipient holds exactly one claim row', () async {
        expect(
          await fetchPostFirstResponseUserIds(
            beaconId: beaconId,
            asEmail: aliceEmail,
            restoreEmail: bobEmail,
          ),
          [bobUserId],
        );
      });

      await logout(tester);
      await loginAs(tester, aliceEmail);
      await goToPath(tester, kPathInbox);
      await runE2eStep('author sees the first-responses row of this Post', () async {
        // The app locale follows the browser, so accept either headline.
        final headlines = [
          for (final code in ['ru', 'en'])
            (await L10n.delegate.load(Locale(code))).postRowFirstResponses,
        ];
        final row = find.byWidgetPredicate(
          (w) => w is PostAttentionRow && w.receipt.beaconId == beaconId,
        );
        await pumpUntilVisible(tester, row, label: 'row of the replied Post');
        expect(
          find.descendant(
            of: row,
            matching: find.byWidgetPredicate(
              (w) => w is Text && headlines.contains(w.data),
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(of: row, matching: find.textContaining(postBody)),
          findsWidgets,
        );
      });

      await runE2eStep('author sees the reply from Bob in the Post conversation', () async {
        await goToDeepLink(tester, '$kPathBeaconView/$beaconId');
        final tile = find.byWidgetPredicate(
          (w) =>
              w is RoomMessageTile &&
              w.message.beaconId == beaconId &&
              w.message.authorId == bobUserId &&
              w.message.body == replyText,
        );
        await pumpUntilVisible(tester, tile, label: 'Bob reply tile');
      });
    },
  );
}
