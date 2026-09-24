import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_message_receipt.dart';

void main() {
  const myUserId = 'me';

  RoomMessage message({
    required String id,
    required String authorId,
    required DateTime createdAt,
    int? systemMessageKind,
  }) =>
      RoomMessage(
        id: id,
        beaconId: 'beacon-1',
        authorId: authorId,
        body: 'body',
        createdAt: createdAt,
        systemMessageKind: systemMessageKind,
      );

  RoomReceiptIndex index({
    Map<String, DateTime> watermarks = const {},
    Set<String> pendingLocalIds = const {},
  }) =>
      RoomReceiptIndex(
        myUserId: myUserId,
        watermarks: watermarks,
        pendingLocalIds: pendingLocalIds,
      );

  group('RoomReceiptIndex.receiptFor', () {
    final createdAt = DateTime.utc(2026, 3, 10, 14, 30);

    test('returns null for another author message', () {
      final receipt = index().receiptFor(
        message(
          id: 'm-peer',
          authorId: 'peer',
          createdAt: createdAt,
        ),
      );
      expect(receipt, isNull);
    });

    test('returns null for system message', () {
      final receipt = index().receiptFor(
        message(
          id: 'm-system',
          authorId: myUserId,
          createdAt: createdAt,
          systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
        ),
      );
      expect(receipt, isNull);
    });

    test('local: id is pending even when peer watermark covers createdAt', () {
      final receipt = index(
        watermarks: {'peer-a': createdAt},
      ).receiptFor(
        message(
          id: 'local:optimistic-1',
          authorId: myUserId,
          createdAt: createdAt,
        ),
      );
      expect(receipt, isNotNull);
      expect(receipt!.state, RoomMessageReceiptState.pending);
    });

    test('pendingLocalIds forces pending even when peer watermark covers createdAt',
        () {
      final receipt = index(
        watermarks: {'peer-a': createdAt},
        pendingLocalIds: {'server-id-still-sending'},
      ).receiptFor(
        message(
          id: 'server-id-still-sending',
          authorId: myUserId,
          createdAt: createdAt,
        ),
      );
      expect(receipt, isNotNull);
      expect(receipt!.state, RoomMessageReceiptState.pending);
    });

    test('peer watermark equal to createdAt is read', () {
      final receipt = index(
        watermarks: {'peer-a': createdAt},
      ).receiptFor(
        message(
          id: 'm-own',
          authorId: myUserId,
          createdAt: createdAt,
        ),
      );
      expect(receipt, isNotNull);
      expect(receipt!.state, RoomMessageReceiptState.read);
      expect(receipt.readerIds, ['peer-a']);
    });

    test('peer watermark one millisecond before createdAt is sent', () {
      final receipt = index(
        watermarks: {
          'peer-a': createdAt.subtract(const Duration(milliseconds: 1)),
        },
      ).receiptFor(
        message(
          id: 'm-own',
          authorId: myUserId,
          createdAt: createdAt,
        ),
      );
      expect(receipt, isNotNull);
      expect(receipt!.state, RoomMessageReceiptState.sent);
      expect(receipt.readerIds, isEmpty);
    });

    test('only the viewer watermark covering message is sent', () {
      final receipt = index(
        watermarks: {myUserId: createdAt},
      ).receiptFor(
        message(
          id: 'm-own',
          authorId: myUserId,
          createdAt: createdAt,
        ),
      );
      expect(receipt, isNotNull);
      expect(receipt!.state, RoomMessageReceiptState.sent);
      expect(receipt.readerIds, isEmpty);
    });

    test('empty watermark map yields sent for own non-pending message', () {
      final receipt = index().receiptFor(
        message(
          id: 'm-own',
          authorId: myUserId,
          createdAt: createdAt,
        ),
      );
      expect(receipt, isNotNull);
      expect(receipt!.state, RoomMessageReceiptState.sent);
      expect(receipt.readerIds, isEmpty);
    });

    test('readerIds sorted by watermark time descending and exclude viewer', () {
      final earlier = DateTime.utc(2026, 3, 10, 14, 0);
      final later = DateTime.utc(2026, 3, 10, 15, 0);
      final receipt = index(
        watermarks: {
          'peer-slow': earlier,
          'peer-fast': later,
          myUserId: later,
        },
      ).receiptFor(
        message(
          id: 'm-own',
          authorId: myUserId,
          createdAt: earlier,
        ),
      );
      expect(receipt, isNotNull);
      expect(receipt!.state, RoomMessageReceiptState.read);
      expect(receipt.readerIds, ['peer-fast', 'peer-slow']);
    });

    test('lists reader with room_access none (no membership filter)', () {
      const outsiderId = 'user-room-access-none';
      final receipt = index(
        watermarks: {outsiderId: createdAt},
      ).receiptFor(
        message(
          id: 'm-own',
          authorId: myUserId,
          createdAt: createdAt,
        ),
      );
      expect(receipt, isNotNull);
      expect(receipt!.state, RoomMessageReceiptState.read);
      expect(receipt.readerIds, [outsiderId]);
    });
  });
}
