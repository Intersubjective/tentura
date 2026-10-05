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

    // Chat is the primary pane; Now is the trailing supporting pane.
    final expanded = TenturaTokens.light.applyWindowClass(
      WindowClass.expanded,
    );

    test('without availableWidth falls back to the pane floor', () {
      expect(beaconViewNowSplitPaneWidth(expanded), 360);
      expect(
        beaconViewNowSplitPaneWidth(expanded, preferredWidth: 420),
        420,
      );
    });

    test('defaults to 40% of the split, within 400..640', () {
      expect(
        beaconViewNowSplitPaneWidth(expanded, availableWidth: 900),
        400,
      );
      expect(
        beaconViewNowSplitPaneWidth(expanded, availableWidth: 1200),
        480,
      );
      expect(
        beaconViewNowSplitPaneWidth(expanded, availableWidth: 2000),
        kBeaconSplitNowPaneMaxDefaultWidth,
      );
    });

    test('embedded tight split allows a 280px pane floor', () {
      expect(
        beaconViewNowSplitPaneWidth(
          expanded,
          availableWidth: 560,
          minPaneWidth: 280,
          preferredWidth: 200,
        ),
        280,
      );
    });

    test('honors preferred width while the chat keeps its floor', () {
      expect(
        beaconViewNowSplitPaneWidth(
          expanded,
          availableWidth: 1200,
          preferredWidth: 600,
        ),
        600,
      );
      expect(
        beaconViewNowSplitPaneWidth(
          expanded,
          availableWidth: 1200,
          preferredWidth: 1000,
        ),
        840,
      );
      expect(
        beaconViewNowSplitPaneWidth(
          expanded,
          availableWidth: 1200,
          preferredWidth: 100,
        ),
        360,
      );
    });

    test('when both floors cannot fit, the chat shrinks so Now keeps it', () {
      expect(
        beaconViewNowSplitPaneWidth(
          expanded,
          availableWidth: 478,
          preferredWidth: 400,
        ),
        360,
      );
      expect(
        beaconViewNowSplitPaneWidth(expanded, availableWidth: 300),
        300,
      );
    });
  });
}
