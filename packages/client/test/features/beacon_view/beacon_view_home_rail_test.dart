import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'beacon_view_screen_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    await registerBeaconViewHarnessGetIt();
  });

  tearDown(() async {
    await unregisterBeaconViewHarnessGetIt();
  });

  testWidgets(
    'expanded-window home rail shows Constellation, not the retired Updates tab',
    (tester) async {
      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessExpanded,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
      );

      expect(find.text('Constellation'), findsOneWidget);
      expect(find.text('Updates'), findsNothing);
      expect(find.byIcon(Icons.hub_outlined), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsNothing);
    },
  );
}
