import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/entity/room_seen_outcome.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

import '../../support/test_realtime_sync.dart';
import 'fake_coordination_item_case.dart';

void main() {
  late FakeBeaconThreadsRepository room;
  late RoomReadWatermarkStore watermark;
  late BeaconThreadsCase case_;
  late TestRealtimeSyncPort realtimePort;
  late RealtimeSyncCase realtimeSyncCase;

  const beaconId = 'b-room';
  const messageId = 'msg-1';

  setUp(() {
    room = FakeBeaconThreadsRepository();
    watermark = RoomReadWatermarkStore.testing();
    final realtime = buildTestRealtimeSync();
    realtimePort = realtime.port;
    realtimeSyncCase = realtime.case_;
    case_ = BeaconThreadsCase(
      room,
      _FakeBeaconFactCardRepository(),
      _FakePollingRepository(),
      _FakeBeaconRoomHintsRepository(),
      watermark,
      const FakeCoordinationItemCaseForRoom(),
      realtimeSyncCase,
      env: const Env(),
      logger: Logger('test'),
    );
  });

  tearDown(() async {
    await watermark.dispose();
    await realtimePort.dispose();
  });

  group('createMessage', () {
    test('no-ops when body is blank and uploads empty', () async {
      final id = await case_.createMessage(beaconId: beaconId, body: '   ');

      expect(id, isNull);
      expect(room.createMessageCalls, 0);
      expect(room.addAttachmentCalls, 0);
    });

    test('sends text-only without attachment', () async {
      final id = await case_.createMessage(beaconId: beaconId, body: 'hello');

      expect(id, messageId);
      expect(room.createMessageCalls, 1);
      expect(room.lastCreateBody, 'hello');
      expect(room.lastFirstAttachment, isNull);
      expect(room.addAttachmentCalls, 0);
    });

    test('passes single pending upload as first attachment only', () async {
      final upload = _upload('one.png');

      await case_.createMessage(
        beaconId: beaconId,
        body: 'see file',
        uploads: [upload],
      );

      expect(room.createMessageCalls, 1);
      expect(room.lastFirstAttachment, upload);
      expect(room.addAttachmentCalls, 0);
    });

    test('sends upload-only message when body is blank', () async {
      final upload = _upload('only.bin');

      await case_.createMessage(
        beaconId: beaconId,
        body: '',
        uploads: [upload],
      );

      expect(room.createMessageCalls, 1);
      expect(room.lastFirstAttachment, upload);
      expect(room.addAttachmentCalls, 0);
    });

    test('attaches extras after createMessage returns id', () async {
      final first = _upload('a.png');
      final second = _upload('b.png');
      final third = _upload('c.png');

      await case_.createMessage(
        beaconId: beaconId,
        body: 'multi',
        uploads: [first, second, third],
      );

      expect(room.createMessageCalls, 1);
      expect(room.lastFirstAttachment, first);
      expect(room.addAttachmentCalls, 2);
      expect(room.addedAttachments.map((e) => e.upload.fileName), [
        'b.png',
        'c.png',
      ]);
      expect(
        room.addedAttachments.every((e) => e.messageId == messageId),
        isTrue,
      );
    });

    test('propagates createMessage failure without retry', () async {
      room.createMessageError = StateError('network');

      await expectLater(
        case_.createMessage(beaconId: beaconId, body: 'hi'),
        throwsA(isA<StateError>()),
      );
      expect(room.createMessageCalls, 1);
      expect(room.addAttachmentCalls, 0);
    });

    test('propagates extra attachment failure without retry', () async {
      room.addAttachmentError = StateError('upload failed');

      await expectLater(
        case_.createMessage(
          beaconId: beaconId,
          body: 'two files',
          uploads: [_upload('a.png'), _upload('b.png')],
        ),
        throwsA(isA<StateError>()),
      );
      expect(room.createMessageCalls, 1);
      expect(room.addAttachmentCalls, 1);
    });
  });

  group('markRoomSeenIfAllowed', () {
    test('confirms General watermark on success', () async {
      final readAt = DateTime.utc(2026, 6, 25, 12);
      final persisted = DateTime.utc(2026, 6, 25, 12, 1);
      room.markThreadSeenResult = persisted;

      final outcome = await case_.markRoomSeenIfAllowed(
        beaconId: beaconId,
        readThroughAt: readAt,
      );

      expect(outcome, isA<RoomSeenSucceeded>());
      expect((outcome as RoomSeenSucceeded).persistedAt, persisted);
      expect(room.lastMarkThreadId, RequestThread.generalId);
      expect(
        watermark.syncedAt(beaconId, threadId: RequestThread.generalId),
        persisted,
      );
      expect(watermark.hasPendingSync(beaconId), isFalse);
    });

    test('derives semantic threadId and confirms keyed watermark', () async {
      const itemId = 'item-semantic';
      final readAt = DateTime.utc(2026, 6, 26, 12);
      final persisted = DateTime.utc(2026, 6, 26, 12, 5);
      room.markThreadSeenResult = persisted;
      watermark.observeReadThrough(beaconId, readAt, threadId: itemId);

      final outcome = await case_.markRoomSeenIfAllowed(
        beaconId: beaconId,
        threadItemId: itemId,
        readThroughAt: readAt,
      );

      expect(outcome, isA<RoomSeenSucceeded>());
      expect(room.lastMarkThreadId, itemId);
      expect(watermark.syncedAt(beaconId, threadId: itemId), persisted);
      expect(
        watermark.syncedAt(beaconId, threadId: RequestThread.generalId),
        isNull,
      );
    });

    test('returns failure without confirming watermark', () async {
      final readAt = DateTime.utc(2026, 6, 25, 12);
      final error = Exception('denied');
      room.markThreadSeenError = error;
      watermark.observeReadThrough(beaconId, readAt);

      final outcome = await case_.markRoomSeenIfAllowed(
        beaconId: beaconId,
        readThroughAt: readAt,
      );

      expect(outcome, isA<RoomSeenFailed>());
      expect((outcome as RoomSeenFailed).error, error);
      expect(watermark.hasPendingSync(beaconId), isTrue);
    });

    test(
      'stale persisted response does not regress semantic watermark',
      () async {
        const itemId = 'item-stale';
        final local = DateTime.utc(2026, 7, 1, 18);
        final stale = DateTime.utc(2026, 7, 1, 12);
        room.markThreadSeenResult = stale;
        watermark.observeReadThrough(beaconId, local, threadId: itemId);

        await case_.markRoomSeenIfAllowed(
          beaconId: beaconId,
          threadItemId: itemId,
          readThroughAt: local,
        );

        expect(watermark.readThrough(beaconId, threadId: itemId), local);
        expect(watermark.syncedAt(beaconId, threadId: itemId), local);
      },
    );
  });

  group('realtime convergence', () {
    test('forwards catch-up without mutating room seen state', () async {
      final events = <void>[];
      final sub = case_.catchUps.listen(events.add);
      addTearDown(sub.cancel);

      realtimePort.emitCatchUp();
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(room.markThreadSeenCalls, 0);
    });

    test('records a server read-through without writing it back', () {
      final seenAt = DateTime.utc(2026, 7, 14);

      case_.observeServerReadThrough(beaconId, seenAt);

      expect(case_.readThrough(beaconId), seenAt);
      expect(room.markThreadSeenCalls, 0);
    });
  });
}

RoomPendingUpload _upload(String fileName) => RoomPendingUpload(
  bytes: Uint8List.fromList([1, 2, 3]),
  fileName: fileName,
  mimeType: 'application/octet-stream',
);

class FakeBeaconThreadsRepository extends Fake
    implements BeaconThreadsRepository {
  int createMessageCalls = 0;
  int addAttachmentCalls = 0;
  String? lastCreateBeaconId;
  String? lastCreateBody;
  RoomPendingUpload? lastFirstAttachment;
  final List<({String messageId, RoomPendingUpload upload})> addedAttachments =
      [];
  Object? createMessageError;
  Object? addAttachmentError;
  DateTime? markThreadSeenResult;
  Object? markThreadSeenError;
  int markThreadSeenCalls = 0;
  String? lastMarkThreadId;

  @override
  Stream<String> get beaconRoomRefresh => const Stream.empty();

  @override
  Future<String> createMessage({
    required String beaconId,
    required String body,
    String? replyToMessageId,
    String? threadItemId,
    RoomPendingUpload? firstAttachment,
    List<String> explicitMentionUserIds = const [],
    List<int> explicitMentionOffsets = const [],
    List<int> explicitMentionLengths = const [],
  }) async {
    createMessageCalls++;
    lastCreateBeaconId = beaconId;
    lastCreateBody = body;
    lastFirstAttachment = firstAttachment;
    if (createMessageError != null) {
      throw createMessageError!;
    }
    return 'msg-1';
  }

  @override
  Future<void> addMessageAttachment({
    required String beaconId,
    required String messageId,
    required RoomPendingUpload upload,
  }) async {
    addAttachmentCalls++;
    addedAttachments.add((messageId: messageId, upload: upload));
    if (addAttachmentError != null) {
      throw addAttachmentError!;
    }
  }

  @override
  Future<DateTime> markThreadSeen({
    required String beaconId,
    required String threadId,
    required DateTime readThroughAt,
  }) async {
    markThreadSeenCalls++;
    lastMarkThreadId = threadId;
    if (markThreadSeenError != null) {
      throw markThreadSeenError!;
    }
    return markThreadSeenResult ?? readThroughAt;
  }
}

class _FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepository {}

class _FakeBeaconRoomHintsRepository extends Fake
    implements BeaconRoomHintsRepository {}

class _FakePollingRepository extends Fake implements PollingRepository {}
