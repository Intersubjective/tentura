import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
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

  group('Beacon view room derived-from-route state (Phase 2 step 6)', () {
    test('route requests room via viewTab=room', () {
      expect(
        beaconViewRoomRequestedByRoute(
          surface: null,
          viewTab: 'room',
          isDeepLink: null,
          entry: null,
        ),
        isTrue,
      );
    });

    test('route requests room via legacy surface=room query', () {
      expect(
        beaconViewRoomRequestedByRoute(
          surface: 'room',
          viewTab: null,
          isDeepLink: null,
          entry: null,
        ),
        isTrue,
      );
      // Case-insensitive / whitespace-tolerant, matching query-param parsing.
      expect(
        beaconViewRoomRequestedByRoute(
          surface: ' ROOM ',
          viewTab: null,
          isDeepLink: null,
          entry: null,
        ),
        isTrue,
      );
    });

    test('route requests room via room-notification entry provenance', () {
      // isDeepLink must NOT be truthy here: normalizeBeaconViewEntry treats a
      // truthy isDeepLink as an external deep link and ignores `entry`
      // entirely (anti-spoofing) — room-notification provenance is an
      // in-app-only signal.
      expect(
        beaconViewRoomRequestedByRoute(
          surface: null,
          viewTab: null,
          isDeepLink: null,
          entry: kBeaconEntryRoomNotification,
        ),
        isTrue,
      );
      expect(
        beaconViewRoomRequestedByRoute(
          surface: null,
          viewTab: null,
          isDeepLink: 'true',
          entry: kBeaconEntryRoomNotification,
        ),
        isFalse,
        reason: 'truthy isDeepLink overrides entry provenance to deepLink',
      );
    });

    test('route does not request room for other tabs / no markers', () {
      for (final viewTab in [null, 'items', 'people', 'log']) {
        expect(
          beaconViewRoomRequestedByRoute(
            surface: null,
            viewTab: viewTab,
            isDeepLink: null,
            entry: null,
          ),
          isFalse,
          reason: 'viewTab=$viewTab should not request room',
        );
      }
    });

    test(
      'legacy room surface only shows when route requests it, split is not '
      'active, and room access is allowed — single derivation drives chrome '
      'and body consistently',
      () {
        expect(
          beaconViewShowsLegacyRoomSurface(
            isSplit: false,
            roomRequestedByRoute: true,
            canNavigateBeaconRoom: true,
          ),
          isTrue,
        );

        // Split always wins: room is co-visible, not a separate surface.
        expect(
          beaconViewShowsLegacyRoomSurface(
            isSplit: true,
            roomRequestedByRoute: true,
            canNavigateBeaconRoom: true,
          ),
          isFalse,
        );

        // No route request — operational, even if access would be allowed.
        expect(
          beaconViewShowsLegacyRoomSurface(
            isSplit: false,
            roomRequestedByRoute: false,
            canNavigateBeaconRoom: true,
          ),
          isFalse,
        );

        // Denied access suppresses the surface even though the URL still
        // asks for room (e.g. mid-flight revocation before the URL/banner
        // side effect lands) — this is what keeps app-bar chrome and body
        // in sync without a manually-cleared flag.
        expect(
          beaconViewShowsLegacyRoomSurface(
            isSplit: false,
            roomRequestedByRoute: true,
            canNavigateBeaconRoom: false,
          ),
          isFalse,
        );
      },
    );
  });
}
