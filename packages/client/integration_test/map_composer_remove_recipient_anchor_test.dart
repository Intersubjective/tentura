import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tentura/features/constellation/domain/constellation_layout.dart';
import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

/// `beacon_participant.room_access` of an admitted Post recipient.
const _roomAccessAdmitted = 3;

/// Scene point where the composer is started; arbitrary, off the canvas
/// centre.
final _dropPoint = Offset(
  constellationCanvasCentrePoint().x + 160,
  constellationCanvasCentrePoint().y - 120,
);

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'map composer hands off to the full Post screen, which reaches only the '
    'remaining recipients',
    (tester) async {
      e2eDrainExceptions = false;
      await launchApp(app.main);
      await pumpBounded(tester);

      // Closure fixture: the author is mutually connected to every helper, so
      // all of them are addressable from the composer (the witness fixture's
      // Bob is only a one-way vouch and never a candidate).
      final fixture = await bootstrapClosureFixture(
        runId: uniqueRunId('map-composer'),
      );
      final aliceEmail = fixture.authorEmail;
      final aliceUserId = fixture.authorUserId;
      final bobEmail = fixture.helperEmails[0];
      final bobUserId = fixture.helperUserIds[0];
      final carolEmail = fixture.helperEmails[1];
      final carolUserId = fixture.helperUserIds[1];
      final daveEmail = fixture.helperEmails[2];
      final daveUserId = fixture.helperUserIds[2];
      final body = uniqueRequestTitle('IT map composer');

      await loginAs(tester, aliceEmail);
      await pumpBounded(tester, frames: 12);
      await openConstellation(tester);

      await runE2eStep('start the composer on the canvas', () async {
        await startMapComposerAt(tester, scene: _dropPoint);
        for (final id in [bobUserId, carolUserId, daveUserId]) {
          await pumpUntilVisible(
            tester,
            find.byKey(Key('constellation.composer.chip.$id')),
            label: 'recipient chip $id',
          );
        }
      });

      await runE2eStep('remove one recipient by tap on its chip', () async {
        await removeMapComposerRecipient(tester, bobUserId);
      });

      await runE2eStep(
        '«Создать» opens the full Post screen with the remaining recipients',
        () async {
          await openFullFormFromMapComposer(tester);
        },
      );

      late String beaconId;
      await runE2eStep('send the Post from the full screen', () async {
        beaconId = await sendPostFromFullForm(tester, body: body);
      });

      await runE2eStep('forward edges go only from Alice to the remaining people', () async {
        expect(
          await fetchForwardEdgePairs(
            beaconId: beaconId,
            asEmail: aliceEmail,
            restoreEmail: aliceEmail,
          ),
          {'$aliceUserId->$carolUserId', '$aliceUserId->$daveUserId'},
        );
      });

      await runE2eStep('only the remaining recipients are admitted', () async {
        Future<int?> accessOf(String userId, String email) =>
            fetchParticipantRoomAccess(
              beaconId: beaconId,
              userId: userId,
              asEmail: email,
              restoreEmail: aliceEmail,
            );
        expect(
          await accessOf(carolUserId, carolEmail),
          _roomAccessAdmitted,
        );
        expect(await accessOf(daveUserId, daveEmail), _roomAccessAdmitted);
        expect(await accessOf(bobUserId, bobEmail), isNull);
      });
    },
  );
}
