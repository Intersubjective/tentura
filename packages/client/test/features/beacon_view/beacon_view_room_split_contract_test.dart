import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/beacon_view/ui/screen/beacon_view_screen.dart';

void main() {
  group('Beacon view expanded thread split contract', () {
    test('splits only for expanded loaded beacons with thread rows', () {
      expect(
        beaconViewUsesExpandedThreadSplit(
          windowClass: WindowClass.expanded,
          showBeaconContent: true,
          hasThreadRows: true,
        ),
        isTrue,
      );

      for (final windowClass in [WindowClass.compact, WindowClass.regular]) {
        expect(
          beaconViewUsesExpandedThreadSplit(
            windowClass: windowClass,
            showBeaconContent: true,
            hasThreadRows: true,
          ),
          isFalse,
        );
      }

      expect(
        beaconViewUsesExpandedThreadSplit(
          windowClass: WindowClass.expanded,
          showBeaconContent: false,
          hasThreadRows: true,
        ),
        isFalse,
      );
      expect(
        beaconViewUsesExpandedThreadSplit(
          windowClass: WindowClass.expanded,
          showBeaconContent: true,
          hasThreadRows: false,
        ),
        isFalse,
      );
    });

    test('without availableWidth uses chat column cap as default', () {
      final expanded = TenturaTokens.light.applyWindowClass(
        WindowClass.expanded,
      );

      expect(beaconViewRoomSplitPaneWidth(expanded), 720);
    });

    test('keeps split room pane at a usable floor', () {
      final narrow = TenturaTokens.light
          .applyWindowClass(WindowClass.expanded)
          .copyWith(chatColumnMaxWidth: 320);

      expect(beaconViewRoomSplitPaneWidth(narrow), 360);
    });

    test('embedded tight split allows 280px room pane floor', () {
      final expanded = TenturaTokens.light.applyWindowClass(
        WindowClass.expanded,
      );

      expect(
        beaconViewRoomSplitPaneWidth(
          expanded,
          availableWidth: 560,
          minPaneWidth: 280,
        ),
        280,
      );
    });

    test('defaults to 42% of available pane width below chat cap', () {
      final expanded = TenturaTokens.light.applyWindowClass(
        WindowClass.expanded,
      );

      expect(
        beaconViewRoomSplitPaneWidth(
          expanded,
          availableWidth: 1200,
        ),
        504,
      );
    });

    test('honors preferred width within clamp bounds', () {
      final expanded = TenturaTokens.light.applyWindowClass(
        WindowClass.expanded,
      );

      expect(
        beaconViewRoomSplitPaneWidth(
          expanded,
          availableWidth: 1200,
          preferredWidth: 480,
        ),
        480,
      );
      expect(
        beaconViewRoomSplitPaneWidth(
          expanded,
          availableWidth: 1200,
          preferredWidth: 900,
        ),
        840,
      );
      expect(
        beaconViewRoomSplitPaneWidth(
          expanded,
          availableWidth: 1200,
          preferredWidth: 100,
        ),
        360,
      );
    });

    test('when both floors cannot fit, shrinks room so ops keeps minPane', () {
      final expanded = TenturaTokens.light.applyWindowClass(
        WindowClass.expanded,
      );

      // 478 total → old clamp forced room to 360 and crushed ops to ~118.
      expect(
        beaconViewRoomSplitPaneWidth(
          expanded,
          availableWidth: 478,
          minPaneWidth: 360,
        ),
        118,
      );
      expect(
        beaconViewRoomSplitPaneWidth(
          expanded,
          availableWidth: 478,
          minPaneWidth: 360,
          preferredWidth: 400,
        ),
        118,
      );
    });
  });
}
