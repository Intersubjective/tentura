// Chat read receipts / room_seen_peer: sender receipt glyph behavior.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_receipt_glyph.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';

import 'support/room_body_harness.dart';

File _clientFile(String relativePath) {
  for (final prefix in const ['../../', '']) {
    final candidate = File('$prefix$relativePath');
    if (candidate.existsSync()) {
      return candidate.absolute;
    }
  }
  throw StateError('Client file not found: $relativePath');
}

Finder receiptGlyphForMessageBody(String body) {
  final bodyText = find.text(body);
  final tile = bodyText.evaluate().isNotEmpty
      ? find.ancestor(
          of: bodyText,
          matching: find.byType(RoomMessageTile),
        )
      : find.byType(RoomMessageTile);
  return find.descendant(
    of: tile,
    matching: find.byType(RoomMessageReceiptGlyph),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewer = Profile(id: 'me', displayName: 'Me');
  const peer = Profile(id: 'peer', displayName: 'Peer');
  final messageCreatedAt = DateTime.utc(2026, 6, 30, 12);

  group('chat read receipts (room_seen_peer)', () {
    test(
      'beacon_room_body_receipts_test uses roomBodyStateForSenderReceipts for multi-member receipts',
      () {
        final source = _clientFile(
          'test/features/beacon_threads/beacon_room_body_receipts_test.dart',
        ).readAsStringSync();
        expect(
          source,
          contains('roomBodyStateForSenderReceipts'),
          reason:
              'sender receipt widget tests must seed admitted discussion members via the shared harness helper',
        );
      },
    );

    test('roomBodyStateForSenderReceipts loads admitted viewer and peer', () {
      final state = roomBodyStateForSenderReceipts(
        myUserId: viewer.id,
        viewer: viewer,
        admittedPeer: peer,
        messages: [
          RoomMessage(
            id: 'own-1',
            beaconId: 'b1',
            authorId: viewer.id,
            author: viewer,
            body: 'Harness fixture',
            createdAt: messageCreatedAt,
          ),
        ],
        readWatermarks: {
          peer.id: RoomReadWatermark(
            userId: peer.id,
            lastSeenAt: messageCreatedAt,
          ),
        },
        readWatermarksLoaded: true,
      );

      expect(state.participantsLoaded, isTrue);
      expect(
        state.participants.any(
          (p) =>
              p.userId == peer.id &&
              p.roomAccess == RoomAccessBits.admitted,
        ),
        isTrue,
        reason: 'peer must be an admitted discussion member for sender receipts',
      );
      expect(
        state.participants.any(
          (p) =>
              p.userId == viewer.id &&
              p.roomAccess == RoomAccessBits.admitted,
        ),
        isTrue,
        reason: 'viewer participant row must be admitted when loaded',
      );
    });

    testWidgets(
      'manual admitted peer fixture shows read glyph for own message (production wiring)',
      (tester) async {
        final message = RoomMessage(
          id: 'own-manual-fixture',
          beaconId: 'b1',
          authorId: viewer.id,
          author: viewer,
          body: 'Own message with manual admitted peer fixture',
          createdAt: messageCreatedAt,
        );
        await pumpBeaconRoomBody(
          tester,
          viewer: viewer,
          enableComposer: false,
          roomState: roomBodyState(
            myUserId: viewer.id,
            messages: [message],
          ).copyWith(
            participants: [
              roomBodyAdmittedParticipant(
                beaconId: 'b1',
                profile: viewer,
                role: BeaconParticipantRoleBits.author,
              ),
              roomBodyAdmittedParticipant(beaconId: 'b1', profile: peer),
            ],
            participantsLoaded: true,
            readWatermarks: {
              peer.id: RoomReadWatermark(
                userId: peer.id,
                lastSeenAt: messageCreatedAt,
              ),
            },
            readWatermarksLoaded: true,
          ),
        );
        await tester.pumpAndSettle();

        final glyph = receiptGlyphForMessageBody(message.body);
        expect(glyph, findsOneWidget);
        expect(
          tester
              .widget<Icon>(
                find.descendant(
                  of: glyph,
                  matching: find.byType(Icon),
                ),
              )
              .icon,
          Icons.done_all,
        );
      },
    );

    testWidgets(
      'roomBodyStateForSenderReceipts shows read glyph for peer watermark',
      (tester) async {
        final message = RoomMessage(
          id: 'own-harness-fixture',
          beaconId: 'b1',
          authorId: viewer.id,
          author: viewer,
          body: 'Own message via sender receipt harness state',
          createdAt: messageCreatedAt,
        );
        await pumpBeaconRoomBody(
          tester,
          viewer: viewer,
          enableComposer: false,
          roomState: roomBodyStateForSenderReceipts(
            myUserId: viewer.id,
            viewer: viewer,
            admittedPeer: peer,
            messages: [message],
            readWatermarks: {
              peer.id: RoomReadWatermark(
                userId: peer.id,
                lastSeenAt: messageCreatedAt,
              ),
            },
            readWatermarksLoaded: true,
          ),
        );
        await tester.pumpAndSettle();

        expect(receiptGlyphForMessageBody(message.body), findsOneWidget);
      },
    );
  });
}
