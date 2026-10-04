import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/main.dart' as app;
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/ui/test_ids.dart';

import 'support/e2e_test_helpers.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a Post converted to a Request by its author becomes kind Request and a '
    'recipient who then offers help is recorded as an offering participant',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);

      final fixture = await bootstrapFixture(
        runId: uniqueRunId('post-convert-offer'),
      );
      final aliceEmail = fixture.authorEmail;
      final bobEmail = fixture.helperEmail;
      final bobUserId = fixture.helperUserId;
      final postBody = uniqueRequestTitle('IT post to convert');
      final requestTitle = uniqueRequestTitle('IT converted request');

      await logout(tester);
      await loginAs(tester, aliceEmail);
      final beaconId = await createPublishedPost(
        body: postBody,
        recipientIds: [bobUserId],
      );

      await runE2eStep('the published item starts as a Post', () async {
        expect(
          await fetchBeaconKind(
            beaconId: beaconId,
            asEmail: aliceEmail,
            restoreEmail: aliceEmail,
          ),
          BeaconKind.post.value,
        );
      });

      await runE2eStep('author converts the Post to a Request', () async {
        await goToDeepLink(tester, '$kPathBeaconView/$beaconId');
        await pumpUntilVisible(tester, find.byIcon(Icons.more_vert));
        await tapAndSettle(tester, find.byIcon(Icons.more_vert).first);
        await tapAndSettle(tester, find.text('Turn into a Request'));
        await tapAndSettle(tester, find.text('Next: details →'));
        final titleField = find.byKey(TestIds.key(TestIds.requestTitle));
        await pumpUntilVisible(tester, titleField);
        await tester.enterText(titleField, requestTitle);
        syncBeaconCreateDraftFields(
          tester,
          title: requestTitle,
          description: 'Converted from a Post in an integration journey',
        );
        await pumpSettleBounded(tester);
        final publish = find.byKey(const Key('BeaconCreate.ConvertButton'));
        await pumpUntilVisible(tester, publish);
        await tapAndSettle(tester, publish);
      });

      await runE2eStep('the converted item is stored as a Request', () async {
        await pumpUntilAsync(
          tester,
          () async =>
              await fetchBeaconKind(
                beaconId: beaconId,
                asEmail: aliceEmail,
                restoreEmail: aliceEmail,
              ) ==
              BeaconKind.request.value,
          label: 'beacon.kind becomes Request',
        );
      });

      await logout(tester);
      await runE2eStep('recipient offers help on the converted Request', () async {
        await offerHelpFromInbox(
          tester,
          fixture: fixture,
          requestTitle: requestTitle,
        );
      });

      await runE2eStep('the offering recipient holds the offered-help role', () async {
        expect(
          await fetchParticipantRole(
            beaconId: beaconId,
            userId: bobUserId,
            asEmail: bobEmail,
            restoreEmail: bobEmail,
          ),
          BeaconParticipantRoleBits.addressee,
        );
        expect(
          await fetchHelpOfferCount(
            beaconId: beaconId,
            userId: bobUserId,
            asEmail: bobEmail,
            restoreEmail: bobEmail,
          ),
          1,
        );
      });
    },
  );
}
