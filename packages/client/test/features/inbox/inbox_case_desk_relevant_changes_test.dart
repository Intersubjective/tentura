import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/realtime/realtime_catch_up.dart';
import 'package:tentura/domain/entity/realtime/realtime_connection_status.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/entity/realtime/realtime_seen_peer.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_fact_card_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_threads_repository.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/polling/data/repository/polling_repository.dart';

import '../../support/test_realtime_sync.dart';
import 'inbox_case_test.dart';

void main() {
  late FakeInboxRepository repo;
  late _DeskRelevantRoomRepository roomRepo;
  late RealtimeSyncCase realtimeSyncCase;
  late TestRealtimeSyncPort realtimePort;
  late InboxCase case_;

  setUp(() {
    repo = FakeInboxRepository();
    roomRepo = _DeskRelevantRoomRepository();
    final sync = buildTestRealtimeSync();
    realtimePort = sync.port;
    realtimeSyncCase = sync.case_;
    case_ = buildTestInboxCase(
      repo,
      _buildDeskRelevantBeaconThreadsCase(roomRepo: roomRepo),
      realtimeSyncCase: realtimeSyncCase,
    );
  });

  tearDown(() async {
    await repo.dispose();
    await roomRepo.dispose();
    await realtimePort.dispose();
  });

  group('InboxCase.deskRelevantChanges roomSeenPeer guard', () {
    test('room invalidation is not desk-relevant', () async {
      final ids = <String>[];
      final sub = case_.deskRelevantChanges.listen(ids.add);

      roomRepo.emitRoomInvalidation(
        BeaconRoomInvalidation(
          beaconId: 'b-room',
          entityType: BeaconRoomEntityType.roomSeenPeer,
          seenPeer: RealtimeSeenPeer(
            userId: 'Upeer00000001',
            lastSeenAt: DateTime.utc(2026, 9, 24),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        ids,
        isEmpty,
        reason: 'peer read-presence must stay out of desk-relevant allow-lists',
      );
      await sub.cancel();
    });

    test('realtime roomSeenPeer change is not desk-relevant', () async {
      final ids = <String>[];
      final sub = case_.deskRelevantChanges.listen(ids.add);

      realtimePort.emitChange(
        RealtimeEntityChange(
          kind: RealtimeEntityKind.roomSeenPeer,
          aggregateId: 'b-realtime',
          operation: RealtimeOperation.update,
          source: RealtimeChangeSource.serverInvalidation,
          seenPeer: RealtimeSeenPeer(
            userId: 'Upeer00000002',
            lastSeenAt: DateTime.utc(2026, 9, 24, 1),
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        ids,
        isEmpty,
        reason: 'InboxCase must not merge roomSeenPeer into desk refetch ids',
      );
      await sub.cancel();
    });

    test('deskRelevantChanges allow-list documents roomSeenPeer exclusion', () {
      final inboxSource = File(
        'lib/features/inbox/domain/use_case/inbox_case.dart',
      ).readAsStringSync();
      final threadsSource = File(
        'lib/features/beacon_threads/domain/use_case/beacon_threads_case.dart',
      ).readAsStringSync();

      expect(
        inboxSource,
        contains('roomSeenPeer'),
        reason: 'InboxCase must document roomSeenPeer outside desk refetch ids',
      );
      expect(
        threadsSource,
        contains('roomSeenPeer'),
        reason:
            'BeaconThreadsCase desk allow-list must document roomSeenPeer '
            'as presence-only',
      );
    });
  });
}

BeaconThreadsCase _buildDeskRelevantBeaconThreadsCase({
  required _DeskRelevantRoomRepository roomRepo,
}) => BeaconThreadsCase(
  roomRepo,
  _DeskRelevantFactCardRepository(),
  _DeskRelevantPollingRepository(),
  _DeskRelevantRoomHintsRepository(),
  RoomReadWatermarkStore.testing(),
  RealtimeSyncCase(_DeskRelevantUnusedRealtimePort()),
  env: const Env(),
  logger: Logger('inbox_case_desk_relevant_changes_test'),
);

class _DeskRelevantRoomRepository implements BeaconThreadsRepository {
  final _roomInvalidations =
      StreamController<BeaconRoomInvalidation>.broadcast();

  @override
  Stream<String> get beaconRoomRefresh =>
      _roomInvalidations.stream.map((e) => e.beaconId);

  @override
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations =>
      _roomInvalidations.stream;

  void emitRoomInvalidation(BeaconRoomInvalidation invalidation) {
    _roomInvalidations.add(invalidation);
  }

  @override
  Future<void> dispose() => _roomInvalidations.close();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeskRelevantFactCardRepository implements BeaconFactCardRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeskRelevantPollingRepository implements PollingRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeskRelevantRoomHintsRepository implements BeaconRoomHintsRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _DeskRelevantUnusedRealtimePort implements RealtimeSyncPort {
  @override
  Stream<RealtimeCatchUp> get catchUps => const Stream.empty();

  @override
  Stream<RealtimeConnectionStatus> get connectionStatuses =>
      const Stream.empty();

  @override
  Stream<RealtimeEntityChange> get entityChanges => const Stream.empty();

  @override
  void requestCatchUp(RealtimeCatchUpReason reason) {}

  @override
  Future<void> dispose() async {}
}
