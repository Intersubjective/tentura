import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_room/ui/coordination_room_navigation.dart';

void main() {
  group('canNestItemDiscussionInRoomPane', () {
    test('nests in expanded split', () {
      expect(
        canNestItemDiscussionInRoomPane(
          isSplit: true,
          showLegacyRoomSurface: false,
          embedded: false,
          embeddedRoomOpen: false,
        ),
        isTrue,
      );
    });

    test('nests in legacy full-bleed room', () {
      expect(
        canNestItemDiscussionInRoomPane(
          isSplit: false,
          showLegacyRoomSurface: true,
          embedded: false,
          embeddedRoomOpen: false,
        ),
        isTrue,
      );
    });

    test('nests when embedded room is open', () {
      expect(
        canNestItemDiscussionInRoomPane(
          isSplit: false,
          showLegacyRoomSurface: false,
          embedded: true,
          embeddedRoomOpen: true,
        ),
        isTrue,
      );
    });

    test('does not nest on compact ops-only standalone', () {
      expect(
        canNestItemDiscussionInRoomPane(
          isSplit: false,
          showLegacyRoomSurface: false,
          embedded: false,
          embeddedRoomOpen: false,
        ),
        isFalse,
      );
    });

    test('does not nest when embedded room is closed', () {
      expect(
        canNestItemDiscussionInRoomPane(
          isSplit: false,
          showLegacyRoomSurface: false,
          embedded: true,
          embeddedRoomOpen: false,
        ),
        isFalse,
      );
    });
  });
}
