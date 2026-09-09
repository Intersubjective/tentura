import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_icons.dart';

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
    'expanded-window home rail shows Field tab, not the retired Updates tab',
    (tester) async {
      await pumpBeaconViewHarness(
        tester,
        size: kBeaconViewHarnessExpanded,
        beaconState: beaconViewHarnessAuthorState(),
        threadsState: beaconViewHarnessThreadsState(),
      );

      expect(find.text('My field'), findsOneWidget);
      expect(find.text('Updates'), findsNothing);
      expect(find.byIcon(TenturaIcons.graph), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsNothing);
    },
  );
}
