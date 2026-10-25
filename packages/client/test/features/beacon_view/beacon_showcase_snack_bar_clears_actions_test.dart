import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_hud_action_button.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

import '../../ui/snack_bar_clearance_support.dart';
import '../beacon_lobby/fake_lobby_port.dart';
import 'beacon_view_screen_harness.dart';

/// #605 (from #406): after Offer help, the «Help offered! Forward it to
/// someone?» bar was drawn across the Request page's own bottom actions, so
/// the page's Forward button (under Offer help / Edit help offer) could not
/// be reached until the bar went away. Bars must float above that panel.
void main() {
  const viewer = 'viewer';
  const nudge = 'Help offered! Forward it to someone?';

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
  });

  Future<void> pumpShowcase(WidgetTester tester, {required Size size}) async {
    // The harness sizes the render surface; the shared clearance checks read
    // the screen from the test view, so give it the same size.
    tester.view
      ..physicalSize = size
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
    GetIt.I.registerSingleton<BeaconLobbyCase>(
      lobbyCaseFor(
        FakeLobbyPort(viewerId: viewer, authorId: kBeaconViewHarnessAuthorId),
        FakeRealtimeSyncPort(),
      ),
    );
    final author = beaconViewHarnessAuthorState();
    await pumpBeaconViewHarness(
      tester,
      size: size,
      beaconState: author.copyWith(
        beacon: author.beacon.copyWith(
          description: 'Help us move on Saturday.',
          accessLevel: BeaconAccessLevel.observer,
          viewerCanForward: true,
        ),
        myProfile: const Profile(id: viewer, displayName: 'Dave'),
        roomParticipants: const [],
      ),
      threadsState: beaconViewHarnessThreadsState(),
    );
    await tester.pumpAndSettle();
  }

  Finder pageAction(String label) => find.descendant(
    of: find.byType(BeaconShowcaseSurface),
    matching: find.widgetWithText(BeaconHudActionButton, label),
  );

  for (final (name, size) in [
    ('phone', kBeaconViewHarnessCompact),
    ('desktop', kBeaconViewHarnessExpanded),
  ]) {
    testWidgets('$name: the Help offered nudge sits above the page Forward '
        'and Offer help buttons', (tester) async {
      await pumpShowcase(tester, size: size);
      expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
      // Precondition: the page's own bottom actions are showing.
      expect(pageAction('Forward'), findsOneWidget);
      expect(pageAction('Offer help'), findsOneWidget);

      // Shown as the help-offer flow shows it: a bar with its own Forward.
      showSnackBar(
        tester.element(find.byType(BeaconShowcaseSurface)),
        text: nudge,
        action: SnackBarAction(label: 'Forward', onPressed: () {}),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 750));

      expectSnackBarClearsButton(
        tester,
        message: nudge,
        button: pageAction('Forward'),
      );
      expectSnackBarClearsButton(
        tester,
        message: nudge,
        button: pageAction('Offer help'),
      );
    });
  }
}
