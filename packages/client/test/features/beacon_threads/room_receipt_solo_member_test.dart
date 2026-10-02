// Chat read receipts (room_seen_peer): no sender receipts when the sender is
// the only admitted member.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_message_receipt.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_receipt_glyph.dart';

import 'support/room_body_harness.dart';

void main() {
  group('chat read receipts (room_seen_peer)', () {
    test(
      'RoomReceiptIndex suppresses sender receipts without another admitted member',
      () {
        final createdAt = DateTime.utc(2026, 9, 24, 12);
        final message = RoomMessage(
          id: 'server-own-solo',
          beaconId: 'b1',
          authorId: 'me',
          body: 'solo discussion',
          createdAt: createdAt,
        );
        const index = RoomReceiptIndex(
          myUserId: 'me',
          watermarks: {},
          pendingLocalIds: {},
        );

        expect(
          index.receiptFor(message),
          isNull,
          reason:
              'beacon_room.md requires ≥1 other discussion member before sender receipts apply',
        );
      },
    );

    testWidgets(
      'BeaconRoomBody hides sender receipt glyph when viewer is the only admitted member',
      (tester) async {
        const viewer = Profile(id: 'me', displayName: 'Me');
        final createdAt = DateTime.utc(2026, 9, 24, 12);
        final message = RoomMessage(
          id: 'own-solo-glyph',
          beaconId: 'b1',
          authorId: viewer.id,
          author: viewer,
          body: 'Only member in discussion',
          createdAt: createdAt,
        );
        final authorParticipant = BeaconParticipant(
          id: 'p-me',
          beaconId: 'b1',
          userId: viewer.id,
          userTitle: 'Me',
          role: BeaconParticipantRoleBits.author,
          status: 0,
          roomAccess: RoomAccessBits.admitted,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        );

        await pumpBeaconRoomBody(
          tester,
          viewer: viewer,
          enableComposer: false,
          roomState:
              roomBodyState(
                myUserId: viewer.id,
                messages: [message],
              ).copyWith(
                participants: [authorParticipant],
                participantsLoaded: true,
                readWatermarksLoaded: true,
              ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(RoomMessageReceiptGlyph), findsNothing);
      },
    );
  });
}
