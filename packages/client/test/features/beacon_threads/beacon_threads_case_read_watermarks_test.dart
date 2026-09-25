// tentura-fpi landing gate acceptance (chat read receipts / room_seen_peer)

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/room_read_watermark.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

import '../../support/test_realtime_sync.dart';

void main() {
  group('fetchMainRoomReadWatermarks', () {
    test('passthrough delegates to BeaconThreadsRepository', () async {
      const beaconId = 'Bbeacon0000001';
      final room = _FakeReadWatermarksRepository();
      final watermark = RoomReadWatermarkStore.testing();
      final realtime = buildTestRealtimeSync();
      addTearDown(watermark.dispose);
      addTearDown(realtime.port.dispose);

      final case_ = BeaconThreadsCase(
        room,
        _FakeBeaconFactCardRepository(),
        _FakePollingRepository(),
        _FakeBeaconRoomHintsRepository(),
        watermark,
        realtime.case_,
        env: const Env(),
        logger: Logger('test'),
      );

      final expected = [
        RoomReadWatermark(
          userId: 'Uuseraaaaaaaa01',
          lastSeenAt: DateTime.utc(2026, 8, 14, 10),
          userTitle: 'Alice',
          userHasPicture: true,
          userImageId: 'img-a',
          userBlurHash: 'hash-a',
          userPicHeight: 100,
          userPicWidth: 200,
        ),
      ];
      room.fetchMainRoomReadWatermarksResult = expected;

      final rows = await case_.fetchMainRoomReadWatermarks(beaconId);

      expect(room.fetchMainRoomReadWatermarksCalls, 1);
      expect(room.lastFetchMainRoomReadWatermarksBeaconId, beaconId);
      expect(rows, expected);
    });
  });
}

class _FakeReadWatermarksRepository extends Fake
    implements BeaconThreadsRepository {
  int fetchMainRoomReadWatermarksCalls = 0;
  String? lastFetchMainRoomReadWatermarksBeaconId;
  List<RoomReadWatermark> fetchMainRoomReadWatermarksResult = const [];

  @override
  Stream<String> get beaconRoomRefresh => const Stream.empty();

  @override
  Future<List<RoomReadWatermark>> fetchMainRoomReadWatermarks(
    String beaconId,
  ) async {
    fetchMainRoomReadWatermarksCalls++;
    lastFetchMainRoomReadWatermarksBeaconId = beaconId;
    return fetchMainRoomReadWatermarksResult;
  }
}

class _FakeBeaconFactCardRepository extends Fake
    implements BeaconFactCardRepository {}

class _FakeBeaconRoomHintsRepository extends Fake
    implements BeaconRoomHintsRepository {}

class _FakePollingRepository extends Fake implements PollingRepository {}
