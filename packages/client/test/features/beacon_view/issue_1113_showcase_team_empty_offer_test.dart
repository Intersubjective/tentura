// #1113: with the viewer's own pending offer, the HELPING strip must not say
// «Nobody yet. Be the first» above the waiting-offer copy.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../beacon_lobby/fake_lobby_port.dart';
import 'beacon_view_screen_harness.dart';

void main() {
  const viewer = 'vera';
  const pendingKey = Key('beaconShowcaseOfferPending');

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
  });

  Future<void> pumpShowcase(WidgetTester tester, {required bool offered}) async {
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
    const me = Profile(id: viewer, displayName: 'QA779 Vera');
    final author = beaconViewHarnessAuthorState();
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessCompact,
      locale: const Locale('ru'),
      beaconState: author.copyWith(
        beacon: author.beacon.copyWith(
          description: 'Help on Saturday.',
          accessLevel: BeaconAccessLevel.observer,
          viewerCanForward: true,
        ),
        myProfile: me,
        helpOffers: [
          if (offered)
            TimelineHelpOffer(
              user: me,
              message: 'I can help Saturday morning.',
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

  testWidgets('375×667 RU: pending offer hides empty-team CTA', (tester) async {
    final l10n = lookupL10n(const Locale('ru'));
    await pumpShowcase(tester, offered: true);

    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
    expect(find.byKey(pendingKey), findsOneWidget);
    expect(find.text(l10n.beaconShowcaseTeamEmpty), findsNothing);
    expect(find.text('Nobody yet. Be the first'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
