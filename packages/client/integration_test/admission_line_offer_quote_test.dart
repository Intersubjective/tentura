import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';
import 'package:tentura/main.dart' as app;

import 'support/e2e_test_helpers.dart';

// A helper writes an offer in the «Offer help» form; the author accepts it in
// People and opens the discussion: the «admitted» line is there, quoting the
// helper's own words, without any reload.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'the admission line in the open discussion quotes the offer typed in '
    'the Offer help form',
    (tester) async {
      await launchApp(app.main);
      await pumpSettleBounded(tester);

      final fixture = await bootstrapFixture(
        runId: uniqueRunId('admit-quote'),
      );
      final title = uniqueRequestTitle('IT admit quote');
      const offerText = 'I can help with software';

      await logout(tester);
      await createAndForwardRequest(
        tester,
        fixture: fixture,
        title: title,
      );

      await logout(tester);
      await offerHelpFromInbox(
        tester,
        fixture: fixture,
        requestTitle: title,
      );

      await logout(tester);
      await acceptHelpOffer(
        tester,
        fixture: fixture,
        requestTitle: title,
      );

      await runE2eStep('author opens the discussion', () async {
        await enterChatIfNeeded(tester);
        final admissionLine = find.byWidgetPredicate(
          (widget) =>
              widget is RoomMessageTile &&
              widget.message.semanticMarker ==
                  BeaconRoomSemanticMarker.participantJoined,
        );
        await pumpUntilVisible(tester, admissionLine);
        final quote = find.descendant(
          of: admissionLine,
          matching: find.textContaining(offerText),
        );
        expect(
          quote,
          findsOneWidget,
          reason: 'the admission line quotes the helper’s offer text',
        );
      });
    },
  );
}
