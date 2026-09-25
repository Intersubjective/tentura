// Issue #178 part 2: `authorSeenAt` delivered with the initial
// `helpOffersWithCoordination` query (not a realtime frame) must show the
// offerer "Seen by the author · awaiting decision" immediately.
//
// Needs the help-offer row record (`CoordinationRepository`
// `fetchHelpOffersWithCoordination` and the test typedef
// `FakeHelpOfferCoordinationRow`) to carry `String? authorSeenAt`.

import 'package:flutter_test/flutter_test.dart';

import 'help_offer_author_seen_test_support.dart';

FakeHelpOfferCoordinationRow _seenOfferRow(DateTime authorSeenAt) => (
  beaconId: kAuthorSeenBeaconId,
  userId: kOfferer.id,
  user: kOfferer,
  message: 'I can help',
  helpType: null,
  roleLabel: null,
  status: 0,
  withdrawReason: null,
  createdAt: kOfferCreatedAt,
  updatedAt: kOfferCreatedAt,
  responseType: null,
  responseUpdatedAt: null,
  responseAuthorUserId: null,
  roomAccess: null,
  admissionAction: null,
  lastDeclineReason: null,
  lastRemoveReason: null,
  stakeState: 0,
  offerKind: 0,
  isDirectAuthorForward: false,
  authorSeenAt: authorSeenAt.toUtc().toIso8601String(),
);

void main() {
  testWidgets(
    'authorSeenAt from the initial help-offer query shows "seen" at once',
    (tester) async {
      final h = (await tester.runAsync(() async {
        final h = AuthorSeenHarness(
          rows: [
            _seenOfferRow(kOfferCreatedAt.add(const Duration(minutes: 5))),
          ],
        );
        await h.load();
        return h;
      }))!;
      await pumpPeople(tester, h.cubit.state);

      expect(find.text(kSeenLabel), findsOneWidget);
      expect(find.text(kNotSeenLabel), findsNothing);
      expect(h.coordination.fetchCalls, 1);

      await tester.runAsync(h.dispose);
    },
  );
}
