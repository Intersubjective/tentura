import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';

import '../beacon_lobby/fake_lobby_port.dart';
import 'beacon_view_screen_harness.dart';

/// #733 (4): someone who is not a member (e.g. a declined invitee) opens the
/// Request during its final check. Offer help and Forward are gone; a muted
/// line says why instead of leaving them to guess.
void main() {
  const viewer = 'carol';
  const noticeKey = Key('beaconShowcaseFinalCheckNotice');

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
  });

  Future<void> pumpShowcase(
    WidgetTester tester, {
    required BeaconStatus status,
  }) async {
    final port = FakeLobbyPort(
      viewerId: viewer,
      authorId: kBeaconViewHarnessAuthorId,
      offerers: <String>{},
    );
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
    GetIt.I.registerSingleton<BeaconLobbyCase>(
      lobbyCaseFor(port, FakeRealtimeSyncPort()),
    );
    final author = beaconViewHarnessAuthorState();
    await pumpBeaconViewHarness(
      tester,
      size: kBeaconViewHarnessCompact,
      beaconState: author.copyWith(
        beacon: author.beacon.copyWith(
          description: 'Garden cleanup on Saturday.',
          accessLevel: BeaconAccessLevel.observer,
          viewerCanForward: status != BeaconStatus.reviewOpen,
          status: status,
        ),
        myProfile: const Profile(id: viewer, displayName: 'Carol'),
        roomParticipants: const [],
      ),
      threadsState: beaconViewHarnessThreadsState(),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('final check: Offer help is gone and the line says why', (
    tester,
  ) async {
    await pumpShowcase(tester, status: BeaconStatus.reviewOpen);
    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
    expect(find.text('Offer help'), findsNothing);
    expect(find.byKey(noticeKey), findsOneWidget);
    expect(find.text('This request is in its final check'), findsOneWidget);
  });

  testWidgets('open Request: no such line (guard)', (tester) async {
    await pumpShowcase(tester, status: BeaconStatus.open);
    expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
    expect(find.byKey(noticeKey), findsNothing);
  });
}
