import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_lobby/domain/use_case/beacon_lobby_case.dart';
import 'package:tentura/features/beacon_lobby/ui/widget/beacon_lobby_entry_row.dart';
import 'package:tentura/features/beacon_view/ui/widget/beacon_showcase_surface.dart';

import '../beacon_lobby/fake_lobby_port.dart';
import 'beacon_view_screen_harness.dart';

/// #526 (D1): someone the Request was sent to asks the author **before**
/// offering help, so the way into Questions must be on the page they see —
/// the showcase — at phone and desktop widths, gated by the server's
/// `BeaconLobbyAccess` probe (never shown to discovery-only readers, Q3).
void main() {
  const recipient = 'recipient';

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
    if (GetIt.I.isRegistered<BeaconLobbyCase>()) {
      await GetIt.I.unregister<BeaconLobbyCase>();
    }
  });

  Future<FakeLobbyPort> pumpShowcase(
    WidgetTester tester, {
    required Size size,
    required bool inAudience,
  }) async {
    final port = FakeLobbyPort(
      viewerId: recipient,
      authorId: kBeaconViewHarnessAuthorId,
      // The fake's stand-in for the server audience: someone the Request
      // was sent to (no help offer needed).
      offerers: {if (inAudience) recipient},
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
      size: size,
      beaconState: author.copyWith(
        beacon: author.beacon.copyWith(
          description: 'Help us move on Saturday.',
          accessLevel: BeaconAccessLevel.observer,
          viewerCanForward: true,
        ),
        myProfile: const Profile(id: recipient, displayName: 'Theo'),
        roomParticipants: const [],
      ),
      threadsState: beaconViewHarnessThreadsState(),
    );
    await tester.pumpAndSettle();
    return port;
  }

  for (final (name, size) in [
    ('phone', kBeaconViewHarnessCompact),
    ('desktop', kBeaconViewHarnessExpanded),
  ]) {
    testWidgets('$name: a recipient who has not offered help sees Questions '
        'on the showcase', (tester) async {
      final port = await pumpShowcase(tester, size: size, inAudience: true);
      expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
      final entry = find.byKey(BeaconLobbyEntryRow.entryKey);
      expect(entry, findsOneWidget);
      expect(
        find.descendant(of: entry, matching: find.text('Questions')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: entry,
          matching: find.textContaining('Ask the author before offering help'),
        ),
        findsOneWidget,
      );
      expect(port.calls, contains('access'));
      // Probing never opens (creates) the Questions scope.
      expect(port.calls, isNot(contains('open')));
    });

    testWidgets('$name: a discovery-only reader gets no Questions entry', (
      tester,
    ) async {
      final port = await pumpShowcase(tester, size: size, inAudience: false);
      expect(find.byType(BeaconShowcaseSurface), findsOneWidget);
      expect(find.byKey(BeaconLobbyEntryRow.entryKey), findsNothing);
      expect(port.calls, contains('access'));
    });
  }
}
