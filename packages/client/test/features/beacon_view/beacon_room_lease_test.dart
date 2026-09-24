import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_room_lease.dart';

const _kBeaconId = 'b-lease-test';
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

RequestThread _generalThread({DateTime? lastSeenAt}) => RequestThread(
  threadId: RequestThread.generalId,
  kind: RequestThreadKind.general,
  lastSeenAt: lastSeenAt ?? _kSeenAt,
);

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

Future<void> _pumpMicrotasks([int rounds = 1]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Future<void> _settleDeferredClear({
  required ThreadHostCubit host,
  required RecordingRoomCubit room,
}) async {
  await _pumpMicrotasks();
  if (room.closeCallCount > 0 && !room.isClosed) {
    room.closeCompleter.complete();
  }
  for (var i = 0; i < 20; i++) {
    await _pumpMicrotasks();
    if (!host.state.switching && host.state.openThreadId == null) return;
    if (room.closeCallCount > 0 && !room.isClosed) {
      room.closeCompleter.complete();
    }
  }
}

void main() {
  group('BeaconRoomLease', () {
    test(
      'two holders: releasing one keeps the room open; releasing both closes once',
      () async {
        final recorder = RoomCubitFactoryRecorder();
        final host = _host(recorder: recorder);
        final lease = BeaconRoomLease(host: host);
        final general = _generalThread();
        final holderA = Object();
        final holderB = Object();

        await lease.acquire(holderA, general);
        await lease.acquire(holderB, general);
        expect(recorder.calls, hasLength(1));

        lease.release(holderA);
        await _pumpMicrotasks(3);
        expect(recorder.created.single.closeCallCount, 0);
        expect(host.state.openThreadId, RequestThread.generalId);

        lease.release(holderB);
        await _settleDeferredClear(host: host, room: recorder.created.single);

        expect(recorder.created.single.closeCallCount, 1);
        expect(host.state.openThreadId, isNull);
        expect(host.roomCubit, isNull);

        await host.close();
      },
    );

    test('reparenting: acquire B before release A never closes the room', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final lease = BeaconRoomLease(host: host);
      final general = _generalThread();
      final holderA = Object();
      final holderB = Object();

      await lease.acquire(holderA, general);
      await lease.acquire(holderB, general);

      lease.release(holderA);
      await _pumpMicrotasks(5);

      expect(recorder.created.single.closeCallCount, 0);
      expect(host.state.openThreadId, RequestThread.generalId);

      lease.release(holderB);
      await _settleDeferredClear(host: host, room: recorder.created.single);
      expect(recorder.created.single.closeCallCount, 1);

      await host.close();
    });

    test(
      'fast flip: release then re-acquire same holder does not close the room',
      () async {
        final recorder = RoomCubitFactoryRecorder();
        final host = _host(recorder: recorder);
        final lease = BeaconRoomLease(host: host);
        final holder = Object();
        final general = _generalThread();

        await lease.acquire(holder, general);
        expect(recorder.calls, hasLength(1));

        lease.release(holder);
        final reacquire = lease.acquire(holder, general);
        await reacquire;
        await _pumpMicrotasks(5);

        expect(recorder.calls, hasLength(1));
        expect(recorder.created.single.closeCallCount, 0);
        expect(host.state.openThreadId, RequestThread.generalId);
        expect(host.roomCubit, isNotNull);

        lease.release(holder);
        lease.dispose();
        recorder.created.single.closeCompleter.complete();
        await host.close();
      },
    );

    test(
      'a second holder joining mid-open awaits the same open (readiness)',
      () async {
        final recorder = RoomCubitFactoryRecorder();
        final host = _host(recorder: recorder);
        final lease = BeaconRoomLease(host: host);
        final general = _generalThread();
        final holderA = Object();
        final holderB = Object();

        // Do not await A: B joins while the open is still in flight.
        final openA = lease.acquire(holderA, general);
        final openB = lease.acquire(holderB, general);

        await Future.wait([openA, openB]);

        // Both callers observe a room that is actually there — this is the
        // precondition for handing a scroll target to prepareThreadScroll.
        expect(host.roomCubit, isNotNull);
        expect(host.state.openThreadId, RequestThread.generalId);
        expect(lease.isReady, isTrue);
        expect(recorder.calls, hasLength(1));

        lease.release(holderA);
        lease.release(holderB);
        await _settleDeferredClear(host: host, room: recorder.created.single);
        await host.close();
      },
    );

    test('acquire is idempotent for the same holder', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final lease = BeaconRoomLease(host: host);
      final holder = Object();
      final general = _generalThread();

      await lease.acquire(holder, general);
      await lease.acquire(holder, general);

      expect(recorder.calls, hasLength(1));

      lease.release(holder);
      await _settleDeferredClear(host: host, room: recorder.created.single);
      expect(recorder.created.single.closeCallCount, 1);

      await host.close();
    });

    test('dispose cancels a pending deferred drop', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final lease = BeaconRoomLease(host: host);
      final holder = Object();
      final general = _generalThread();

      await lease.acquire(holder, general);
      lease.release(holder);
      lease.dispose();
      await _pumpMicrotasks(5);

      expect(recorder.created.single.closeCallCount, 0);
      expect(host.state.openThreadId, RequestThread.generalId);

      recorder.created.single.closeCompleter.complete();
      await host.close();
    });

    test('is safe when the host cubit is already closed', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final lease = BeaconRoomLease(host: host);
      final holder = Object();
      final general = _generalThread();

      await lease.acquire(holder, general);
      recorder.created.single.closeCompleter.complete();
      await host.close();

      await lease.acquire(holder, general);
      lease.release(holder);
      lease.dispose();
    });
  });

  group('ThreadHostCubit ensureGeneral guard', () {
    test('does not early-return over a queued clear', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final general = _generalThread();

      await host.select(general);
      expect(recorder.created, hasLength(1));
      final first = recorder.created.single;

      unawaited(host.clear());
      unawaited(host.ensureGeneral(general));

      first.closeCompleter.complete();
      for (var i = 0; i < 20; i++) {
        await _pumpMicrotasks();
        if (!host.state.switching) break;
        for (final room in recorder.created) {
          if (room.closeCallCount > 0 && !room.isClosed) {
            room.closeCompleter.complete();
          }
        }
      }

      expect(host.state.openThreadId, RequestThread.generalId);
      expect(host.roomCubit, isNotNull);
      expect(host.state.switching, isFalse);

      for (final room in recorder.created) {
        if (!room.isClosed) room.closeCompleter.complete();
      }
      await host.close();
    });

    test('settled duplicate ensureGeneral is a no-op', () async {
      final recorder = RoomCubitFactoryRecorder();
      final host = _host(recorder: recorder);
      final general = _generalThread();

      await host.ensureGeneral(general);
      await host.ensureGeneral(general);

      expect(recorder.calls, hasLength(1));
      expect(host.state.openThreadId, RequestThread.generalId);
      expect(host.state.switching, isFalse);

      recorder.created.single.closeCompleter.complete();
      await host.close();
    });
  });
}
