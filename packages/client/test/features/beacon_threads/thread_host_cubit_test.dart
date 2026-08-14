import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_state.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';

const _kBeaconId = 'b-host-test';
final _kSeenAt = DateTime.utc(2026, 8, 14, 10);

class RecordingRoomCubit extends Mock implements RoomCubit {
  RecordingRoomCubit({
    required String beaconId,
    String? threadItemId,
    DateTime? initialUnreadAnchorAt,
  }) : closeCompleter = Completer<void>(),
       _state = RoomState(
         beaconId: beaconId,
         threadItemId: threadItemId,
         unreadAnchorAt: initialUnreadAnchorAt,
       );

  final RoomState _state;
  final Completer<void> closeCompleter;
  int closeCallCount = 0;
  bool _isClosed = false;

  @override
  RoomState get state => _state;

  @override
  Stream<RoomState> get stream => Stream.value(_state);

  @override
  bool get isClosed => _isClosed;

  @override
  Future<void> close() async {
    closeCallCount++;
    await closeCompleter.future;
    _isClosed = true;
  }
}

class RoomCubitFactoryRecorder {
  final List<RecordingRoomCubit> created = [];
  final List<
    ({
      String beaconId,
      String? threadItemId,
      DateTime? initialUnreadAnchorAt,
    })
  >
  calls = [];

  RecordingRoomCubit call({
    required String beaconId,
    String? threadItemId,
    DateTime? initialUnreadAnchorAt,
  }) {
    calls.add(
      (
        beaconId: beaconId,
        threadItemId: threadItemId,
        initialUnreadAnchorAt: initialUnreadAnchorAt,
      ),
    );
    final cubit = RecordingRoomCubit(
      beaconId: beaconId,
      threadItemId: threadItemId,
      initialUnreadAnchorAt: initialUnreadAnchorAt,
    );
    created.add(cubit);
    return cubit;
  }
}

CoordinationItem _item(String id) => CoordinationItem(
  id: id,
  beaconId: _kBeaconId,
  kind: CoordinationItemKind.ask,
  status: CoordinationItemStatus.open,
  creatorId: 'creator',
  createdAt: DateTime.utc(2026, 1, 1),
  updatedAt: DateTime.utc(2026, 1, 2),
  published: true,
);

RequestThread _generalThread({DateTime? lastSeenAt}) => RequestThread(
  threadId: RequestThread.generalId,
  kind: RequestThreadKind.general,
  lastSeenAt: lastSeenAt ?? _kSeenAt,
);

RequestThread _semanticThread({
  required String itemId,
  DateTime? lastSeenAt,
}) {
  final item = _item(itemId);
  return RequestThread(
    threadId: itemId,
    kind: RequestThreadKind.ask,
    lastSeenAt: lastSeenAt ?? _kSeenAt,
    item: item,
  );
}

ThreadHostCubit _host({RoomCubitFactoryRecorder? recorder}) {
  final factoryRecorder = recorder ?? RoomCubitFactoryRecorder();
  return ThreadHostCubit(
    beaconId: _kBeaconId,
    roomCubitFactory: ({
      required String beaconId,
      String? threadItemId,
      DateTime? initialUnreadAnchorAt,
    }) =>
        factoryRecorder.call(
          beaconId: beaconId,
          threadItemId: threadItemId,
          initialUnreadAnchorAt: initialUnreadAnchorAt,
        ),
  );
}

void main() {
  group('ThreadHostCubit', () {
    test('does not construct next cubit until previous close completes', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);

      await host.select(_generalThread());
      expect(recorder.created, hasLength(1));
      final first = recorder.created.single;

      final secondSelect = host.select(_semanticThread(itemId: 'item-b'));
      expect(recorder.created, hasLength(1));

      first.closeCompleter.complete();
      await secondSelect;

      expect(recorder.created, hasLength(2));
      expect(recorder.calls.last.threadItemId, 'item-b');
      expect(first.closeCallCount, 1);

      recorder.created.last.closeCompleter.complete();
      await host.close();
    });

    test('rapid A→B→C coalesces to one factory call when tail has not run', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);

      final threadA = _semanticThread(itemId: 'item-a');
      final threadB = _semanticThread(itemId: 'item-b');
      final threadC = _semanticThread(itemId: 'item-c');

      unawaited(host.select(threadA));
      unawaited(host.select(threadB));
      final finalSelect = host.select(threadC);

      expect(recorder.calls, isEmpty);
      expect(host.state.selectionGeneration, 3);
      expect(host.state.switching, isTrue);

      await finalSelect;

      expect(recorder.calls, hasLength(1));
      expect(recorder.calls.single.threadItemId, 'item-c');
      expect(host.state.openThreadId, 'item-c');
      expect(host.state.switching, isFalse);
      expect(host.roomCubit?.state.threadItemId, 'item-c');

      recorder.created.single.closeCompleter.complete();
      await host.close();
    });

    test('General passes threadItemId null to factory', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);

      await host.select(_generalThread(lastSeenAt: _kSeenAt));

      expect(recorder.calls.single.threadItemId, isNull);
      expect(recorder.calls.single.beaconId, _kBeaconId);
      expect(recorder.calls.single.initialUnreadAnchorAt, _kSeenAt);
      expect(host.state.openThreadId, RequestThread.generalId);
      expect(host.roomCubit?.state.threadItemId, isNull);

      recorder.created.single.closeCompleter.complete();
      await host.close();
    });

    test('semantic thread passes item id to factory', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);

      await host.select(_semanticThread(itemId: 'semantic-42'));

      expect(recorder.calls.single.threadItemId, 'semantic-42');
      expect(host.state.openThreadId, 'semantic-42');

      recorder.created.single.closeCompleter.complete();
      await host.close();
    });

    test('host close awaits owned cubit close flush', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);

      await host.select(_generalThread());
      final owned = recorder.created.single;
      expect(owned.closeCallCount, 0);

      var hostCloseCompleted = false;
      final hostClose = host.close().then((_) {
        hostCloseCompleted = true;
      });

      await Future<void>.delayed(Duration.zero);
      expect(hostCloseCompleted, isFalse);
      expect(owned.closeCallCount, 1);

      owned.closeCompleter.complete();
      await hostClose;
      expect(hostCloseCompleted, isTrue);
    });

    test('clear closes owned cubit and clears openThreadId', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);

      await host.select(_semanticThread(itemId: 'item-clear'));
      final owned = recorder.created.single;

      final clearFuture = host.clear();
      owned.closeCompleter.complete();
      await clearFuture;

      expect(host.state.openThreadId, isNull);
      expect(host.state.switching, isFalse);
      expect(host.roomCubit, isNull);
      expect(owned.closeCallCount, 1);

      await host.close();
    });
  });
}
