import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_pinned_block.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_surface_tabs.dart';
import 'package:tentura/ui/test_ids.dart';

import 'beacon_view_screen_harness.dart';

/// #159 / #104: insiders get the HUD with tabs, outsiders a showcase with
/// no tab row; the author can preview the showcase from ⋮.
void main() {
  tearDown(unregisterBeaconViewHarnessGetIt);

  testWidgets('an outsider gets the showcase without a tab row', (
    tester,
  ) async {
    final author = beaconViewHarnessAuthorState();
    final state = author.copyWith(
      beacon: author.beacon.copyWith(
        description: 'We build three garden beds at the school.',
        accessLevel: BeaconAccessLevel.observer,
        viewerCanForward: true,
      ),
      myProfile: const Profile(id: 'outsider', displayName: 'Outsider'),
      roomParticipants: const [],
    );
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessCompact,
      beaconState: state,
      threadsState: beaconViewHarnessThreadsState(),
    );

    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
    expect(find.byType(BeaconSurfaceTabs), findsNothing);
    expect(find.byType(BeaconHudPinnedBlock), findsNothing);
    expect(find.text('Harness request'), findsOneWidget);
    expect(
      find.text('We build three garden beds at the school.'),
      findsOneWidget,
    );
    expect(find.text('Author'), findsOneWidget);
    expect(find.text('IN ON IT'), findsOneWidget);
    expect(find.text('Nobody yet. Be the first'), findsOneWidget);
  });

  testWidgets('the author gets the HUD and can preview the showcase', (
    tester,
  ) async {
    final author = beaconViewHarnessAuthorState();
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessCompact,
      beaconState: author.copyWith(
        beacon: author.beacon.copyWith(accessLevel: BeaconAccessLevel.author),
      ),
      threadsState: beaconViewHarnessThreadsState(),
    );

    expect(find.byType(BeaconSurfaceTabs), findsOneWidget);
    expect(find.byType(BeaconHudPinnedBlock), findsOneWidget);
    expect(find.byType(BeaconShowcaseSurface), findsNothing);

    await tester.tap(find.byKey(TestIds.key(TestIds.beaconOverflowMenu)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('How others see it'));
    await tester.pumpAndSettle();

    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
    expect(find.byType(BeaconSurfaceTabs), findsNothing);
    expect(
      find.text('This is how people outside the request see it'),
      findsOneWidget,
    );

    await tester.tap(find.text('Back to my view'));
    await tester.pumpAndSettle();
    expect(find.byType(BeaconSurfaceTabs), findsOneWidget);
  });
}
