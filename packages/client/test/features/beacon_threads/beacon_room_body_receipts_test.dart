import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_receipt_glyph.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';

import 'support/room_body_harness.dart';

// tentura-fpi landing gate acceptance (chat read receipts / room_seen_peer)

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewer = Profile(id: 'me', displayName: 'Me');
  const peer = Profile(id: 'peer', displayName: 'Peer');
  final messageCreatedAt = DateTime.utc(2026, 6, 30, 12, 0);

  RoomMessage ownMessage({
    String id = 'own-1',
    DateTime? createdAt,
  }) =>
      RoomMessage(
        id: id,
        beaconId: 'b1',
        authorId: viewer.id,
        author: viewer,
        body: 'Own message for receipt wiring',
        createdAt: createdAt ?? messageCreatedAt,
      );

  RoomMessage peerMessage() => RoomMessage(
        id: 'peer-1',
        beaconId: 'b1',
        authorId: peer.id,
        author: peer,
        body: 'Peer message without sender receipt',
        createdAt: messageCreatedAt,
      );

  RoomReadWatermark watermark(String userId, DateTime lastSeenAt) =>
      RoomReadWatermark(userId: userId, lastSeenAt: lastSeenAt);

  Finder receiptGlyphForMessageBody(String body) {
    // Inline meta uses Text.rich, so [find.text] often misses the body string.
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

  Icon receiptIcon(WidgetTester tester, Finder glyphFinder) {
    return tester.widget<Icon>(
      find.descendant(of: glyphFinder, matching: find.byType(Icon)),
    );
  }

  String receiptSemanticsLabel(WidgetTester tester, Finder glyphFinder) {
    final semanticsWidgets = tester.widgetList<Semantics>(
      find.descendant(of: glyphFinder, matching: find.byType(Semantics)),
    );
    for (final semantics in semanticsWidgets) {
      final label = semantics.properties.label;
      if (label != null && label.isNotEmpty && !label.contains('\n')) {
        return label;
      }
    }
    fail('receipt semantics label not found under glyph');
  }

  group('BeaconRoomBody sender receipts', () {
    testWidgets(
      'peer read watermark covering own message shows done_all',
      (tester) async {
        final message = ownMessage();
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
              peer.id: watermark(peer.id, message.createdAt),
            },
            readWatermarksLoaded: true,
          ),
        );
        await tester.pumpAndSettle();

        final glyph = receiptGlyphForMessageBody(message.body);
        expect(glyph, findsOneWidget);
        expect(
          receiptIcon(tester, glyph).icon,
          Icons.done_all,
        );
        expect(receiptSemanticsLabel(tester, glyph), 'Read by 1 person');
      },
    );

    testWidgets(
      'only viewer watermark covering own message shows done',
      (tester) async {
        final message = ownMessage();
        final cubit = await pumpBeaconRoomBody(
          tester,
          viewer: viewer,
          enableComposer: false,
          roomState: roomBodyStateForSenderReceipts(
            myUserId: viewer.id,
            viewer: viewer,
            admittedPeer: peer,
            messages: [message],
            readWatermarks: {
              peer.id: watermark(peer.id, message.createdAt),
            },
            readWatermarksLoaded: true,
          ),
        );
        await tester.pumpAndSettle();

        final glyphAfterPeerRead = receiptGlyphForMessageBody(message.body);
        expect(glyphAfterPeerRead, findsOneWidget);
        expect(receiptIcon(tester, glyphAfterPeerRead).icon, Icons.done_all);

        cubit.emitHarnessState(
          cubit.state.copyWith(
            readWatermarks: {
              viewer.id: watermark(viewer.id, message.createdAt),
            },
          ),
        );
        await tester.pumpAndSettle();

        final glyphAfterViewerOnly = receiptGlyphForMessageBody(message.body);
        expect(glyphAfterViewerOnly, findsOneWidget);
        expect(receiptIcon(tester, glyphAfterViewerOnly).icon, Icons.done);
        expect(receiptSemanticsLabel(tester, glyphAfterViewerOnly), 'Sent');
      },
    );

    testWidgets('peer-authored message shows no receipt glyph', (tester) async {
      final message = peerMessage();
      await pumpBeaconRoomBody(
        tester,
        viewer: viewer,
        enableComposer: false,
        roomState: roomBodyState(
          myUserId: viewer.id,
          messages: [message],
        ).copyWith(
          readWatermarks: {
            viewer.id: watermark(viewer.id, message.createdAt),
          },
          readWatermarksLoaded: true,
        ),
      );
      await tester.pumpAndSettle();

      expect(receiptGlyphForMessageBody(message.body), findsNothing);
    });

    testWidgets('local: optimistic own message shows schedule pending glyph',
        (tester) async {
      final message = ownMessage(id: 'local:optimistic-uuid');
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
            peer.id: watermark(peer.id, message.createdAt),
          },
          readWatermarksLoaded: true,
        ),
      );
      await tester.pumpAndSettle();

      final glyph = receiptGlyphForMessageBody(message.body);
      expect(glyph, findsOneWidget);
      expect(receiptIcon(tester, glyph).icon, Icons.schedule);
      expect(receiptSemanticsLabel(tester, glyph), 'Sending…');
    });
  });
}
