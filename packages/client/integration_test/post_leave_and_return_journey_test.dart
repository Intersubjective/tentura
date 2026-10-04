import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

/// `beacon_participant.room_access` values (server `RoomAccessBits`).
const _roomAccessAdmitted = 3;
const _roomAccessLeft = 5;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'recipient leaves a Post conversation and returns from Not interested',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);

      final fixture = await bootstrapFixture(
        runId: uniqueRunId('post-leave-return'),
      );
      final title = uniqueRequestTitle('IT leave return');

      await logout(tester);
      await loginAs(tester, fixture.authorEmail);
      final beaconId = await createPublishedPost(
        body: title,
        recipientIds: [fixture.helperUserId],
      );

      await logout(tester);
      await loginAs(tester, fixture.helperEmail);
      await goToDeepLink(tester, '$kPathBeaconView/$beaconId');
      await pumpUntilVisible(tester, find.byIcon(Icons.more_vert));

      await runE2eStep('recipient starts admitted', () async {
        expect(
          await fetchParticipantRoomAccess(
            beaconId: beaconId,
            userId: fixture.helperUserId,
            asEmail: fixture.helperEmail,
            restoreEmail: fixture.helperEmail,
          ),
          _roomAccessAdmitted,
        );
      });

      await runE2eStep('leave conversation stores room_access 5', () async {
        await leavePostConversation(tester);
        await pumpUntilAsync(
          tester,
          () async =>
              await fetchParticipantRoomAccess(
                beaconId: beaconId,
                userId: fixture.helperUserId,
                asEmail: fixture.helperEmail,
                restoreEmail: fixture.helperEmail,
              ) ==
              _roomAccessLeft,
        );
      });

      await runE2eStep('return from Not interested restores room_access 3', () async {
        await returnToPostFromNotInterested(tester, beaconId: beaconId);
        await pumpUntilAsync(
          tester,
          () async =>
              await fetchParticipantRoomAccess(
                beaconId: beaconId,
                userId: fixture.helperUserId,
                asEmail: fixture.helperEmail,
                restoreEmail: fixture.helperEmail,
              ) ==
              _roomAccessAdmitted,
        );
      });
    },
  );
}
