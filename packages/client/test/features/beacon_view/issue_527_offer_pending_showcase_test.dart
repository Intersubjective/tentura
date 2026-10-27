// #527: right after Offer help the helper saw "Your offer is with the author",
// none of their own words, and Withdraw only under More actions. The waiting
// state now names the author, quotes the helper's offer (at most two lines)
// and shows a "Withdraw offer" button that opens the usual withdraw dialog.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';

import '../beacon_lobby/fake_lobby_port.dart';
import 'beacon_view_screen_harness.dart';

void main() {
  const viewer = 'dave';
  const offerText = 'I have a van! Can do 10-12 on Saturday.';
  const pendingKey = Key('beaconShowcaseOfferPending');
  const quoteKey = Key('beaconShowcaseOfferPendingMessage');
  const withdrawKey = Key('beaconShowcaseWithdrawOffer');

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
  });

  Future<void> pumpShowcase(
    WidgetTester tester, {
    required bool offered,
    String message = offerText,
  }) async {
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
    GetIt.I.registerSingleton<BeaconLobbyCase>(
      lobbyCaseFor(
        FakeLobbyPort(
          viewerId: viewer,
          authorId: kBeaconViewHarnessAuthorId,
          offerers: {if (offered) viewer},
        ),
        FakeRealtimeSyncPort(),
      ),
    );
    const me = Profile(id: viewer, displayName: 'Dave');
    final author = beaconViewHarnessAuthorState();
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessCompact,
      beaconState: author.copyWith(
        beacon: author.beacon.copyWith(
          description: 'Help us move on Saturday.',
          accessLevel: BeaconAccessLevel.observer,
          viewerCanForward: true,
        ),
        myProfile: me,
        helpOffers: [
          if (offered)
            TimelineHelpOffer(
              user: me,
              message: message,
              createdAt: kBeaconViewHarnessNow,
              updatedAt: kBeaconViewHarnessNow,
            ),
        ],
        isHelpOffered: offered,
      ),
      threadsState: beaconViewHarnessThreadsState(),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a waiting offer names the author and quotes the offer', (
    tester,
  ) async {
    await pumpShowcase(tester, offered: true);
    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);

    expect(find.byKey(pendingKey), findsOneWidget);
    expect(find.text('Your offer is with Author'), findsOneWidget);
    expect(find.text('Your offer is with the author'), findsNothing);

    expect(find.byKey(quoteKey), findsOneWidget);
    expect(find.text('“$offerText”'), findsOneWidget);
    expect(tester.widget<Text>(find.byKey(quoteKey)).maxLines, 2);
  });

  testWidgets('Withdraw offer is visible and opens the withdraw dialog', (
    tester,
  ) async {
    await pumpShowcase(tester, offered: true);

    final withdraw = find.byKey(withdrawKey);
    expect(withdraw, findsOneWidget);
    expect(
      find.descendant(of: withdraw, matching: find.text('Withdraw offer')),
      findsOneWidget,
    );

    await tester.ensureVisible(withdraw);
    await tester.tap(withdraw);
    await tester.pumpAndSettle();
    expect(find.text('Withdraw help offer'), findsOneWidget);
  });

  testWidgets('an offer with no text shows no empty quote', (tester) async {
    await pumpShowcase(tester, offered: true, message: '  ');

    expect(find.byKey(pendingKey), findsOneWidget);
    expect(find.byKey(quoteKey), findsNothing);
    expect(find.byKey(withdrawKey), findsOneWidget);
  });

  // Guard: someone who has not offered sees none of it.
  testWidgets('no offer: no waiting line, quote or Withdraw offer', (
    tester,
  ) async {
    await pumpShowcase(tester, offered: false);
    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);

    expect(find.byKey(pendingKey), findsNothing);
    expect(find.byKey(quoteKey), findsNothing);
    expect(find.byKey(withdrawKey), findsNothing);
  });
}
