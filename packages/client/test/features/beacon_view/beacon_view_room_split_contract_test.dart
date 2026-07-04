import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';

void main() {
  group('Beacon view expanded room split contract', () {
    test('splits only for expanded loaded beacons with room access', () {
      expect(
        beaconViewUsesExpandedRoomSplit(
          windowClass: WindowClass.expanded,
          showBeaconContent: true,
          canNavigateBeaconRoom: true,
        ),
        isTrue,
      );

      for (final windowClass in [WindowClass.compact, WindowClass.regular]) {
        expect(
          beaconViewUsesExpandedRoomSplit(
            windowClass: windowClass,
            showBeaconContent: true,
            canNavigateBeaconRoom: true,
          ),
          isFalse,
        );
      }

      expect(
        beaconViewUsesExpandedRoomSplit(
          windowClass: WindowClass.expanded,
          showBeaconContent: false,
          canNavigateBeaconRoom: true,
        ),
        isFalse,
      );
      expect(
        beaconViewUsesExpandedRoomSplit(
          windowClass: WindowClass.expanded,
          showBeaconContent: true,
          canNavigateBeaconRoom: false,
        ),
        isFalse,
      );
    });

    test('caps split room pane below the chat column cap', () {
      final expanded = TenturaTokens.light.applyWindowClass(
        WindowClass.expanded,
      );

      expect(beaconViewRoomSplitPaneWidth(expanded), 560);
    });

    test('keeps split room pane at a usable floor', () {
      final narrow = TenturaTokens.light
          .applyWindowClass(WindowClass.expanded)
          .copyWith(chatColumnMaxWidth: 320);

      expect(beaconViewRoomSplitPaneWidth(narrow), 360);
    });
  });
}
