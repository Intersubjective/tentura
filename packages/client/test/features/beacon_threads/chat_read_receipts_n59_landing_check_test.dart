// Chat read receipts (room_seen_peer): contract coverage + sender receipt
// glyph behavior.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_message_receipt.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_receipt_glyph.dart';

import 'support/room_body_harness.dart';

File _repoContractFile() {
  for (final path in const [
    '../../docs/contracts/realtime-entity-contract.json',
    'docs/contracts/realtime-entity-contract.json',
  ]) {
    final file = File(path);
    if (file.existsSync()) {
      return file.absolute;
    }
  }
  throw StateError('Realtime entity contract manifest not found');
}

Map<String, dynamic> _roomSeenPeerContractEntry() {
  final contract =
      jsonDecode(_repoContractFile().readAsStringSync()) as Map<String, dynamic>;
  final kinds = (contract['kinds']! as List).cast<Map>();
  return Map<String, dynamic>.from(
    kinds.singleWhere((entry) => entry['wireKind'] == 'room_seen_peer'),
  );
}

void main() {
  group('chat read receipts (room_seen_peer)', () {
    test(
      'room_seen_peer contract lists threads and inbox desk guard acceptance tests',
      () {
        final tests =
            (_roomSeenPeerContractEntry()['tests']! as List).cast<String>();
        expect(
          tests,
          contains(
            'packages/client/test/features/beacon_threads/threads_cubit_test.dart',
          ),
          reason: 'roomSeenPeer must not refetch threads (threads_cubit_test)',
        );
        expect(
          tests,
          contains(
            'packages/client/test/features/inbox/inbox_case_desk_relevant_changes_test.dart',
          ),
          reason:
              'roomSeenPeer must stay out of desk refetch ids (inbox_case test)',
        );
      },
    );

    test(
      'room_seen_peer contract impacts include chat sender receipt convergence',
      () {
        final impacts =
            (_roomSeenPeerContractEntry()['impacts']! as List).cast<String>();
        expect(
          impacts,
          contains('chat_receipts'),
          reason:
              'peer watermark patches must map to sender receipt glyphs per issue #178',
        );
      },
    );

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
          roomState: roomBodyState(
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
