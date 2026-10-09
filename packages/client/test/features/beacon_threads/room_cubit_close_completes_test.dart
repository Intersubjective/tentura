// Closing a real RoomCubit, directly or through its ThreadHostCubit, must
// complete rather than leave the close future pending.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/beacon_threads/domain/entity/request_thread.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/thread_host_cubit.dart';

import 'room_cubit_fakes.dart';

const _closeTimeout = Duration(seconds: 5);

void main() {
  late FakeBeaconThreadsRepository repo;

  setUp(() {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    repo = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
  });

  group('RoomCubit.close', () {
    test('completes after the room has loaded', () async {
      final cubit = roomCubitForTest(repo);
      await awaitRoomCubitLoad(cubit);

      await cubit.close().timeout(_closeTimeout);

      expect(cubit.isClosed, isTrue);
    });

    test(
      'completes while a listener is still attached to its stream',
      () async {
        final cubit = roomCubitForTest(repo);
        final sub = cubit.stream.listen((_) {});
        await awaitRoomCubitLoad(cubit);

        await cubit.close().timeout(_closeTimeout);
        await sub.cancel();

        expect(cubit.isClosed, isTrue);
      },
    );
  });

  group('ThreadHostCubit.close', () {
    test('closes the hosted room cubit and completes', () async {
      final host = ThreadHostCubit(
        beaconId: kRoomCubitFakeBeaconId,
        roomCubitFactory:
            ({
              required beaconId,
              threadItemId,
              initialUnreadAnchorAt,
              capabilities = const RoomCapabilities.request(),
            }) => roomCubitForTest(repo),
      );
      await host.select(
        RequestThread(
          threadId: RequestThread.generalId,
          kind: RequestThreadKind.general,
          lastSeenAt: DateTime.utc(2026, 8, 14, 10),
        ),
      );
      final room = host.roomCubit!;
      await awaitRoomCubitLoad(room);

      await host.close().timeout(_closeTimeout);

      expect(room.isClosed, isTrue);
      expect(host.isClosed, isTrue);
    });
  });

  group('under a widget-test fake clock', () {
    ThreadHostCubit hostForTest() => ThreadHostCubit(
      beaconId: kRoomCubitFakeBeaconId,
      roomCubitFactory:
          ({
            required beaconId,
            threadItemId,
            initialUnreadAnchorAt,
            capabilities = const RoomCapabilities.request(),
          }) => roomCubitForTest(repo),
    );

    RequestThread generalThread() => RequestThread(
      threadId: RequestThread.generalId,
      kind: RequestThreadKind.general,
      lastSeenAt: DateTime.utc(2026, 8, 14, 10),
    );

    testWidgets('RoomCubit.close completes under a fake clock', (tester) async {
      final cubit = roomCubitForTest(repo);
      await tester.pump(const Duration(seconds: 1));

      final done = await _pumpUntilCompleted(tester, cubit.close());

      expect(done, isTrue, reason: 'close() future never completed');
      expect(cubit.isClosed, isTrue);
    });

    testWidgets('RoomCubit.close completes when called right after creation', (
      tester,
    ) async {
      final cubit = roomCubitForTest(repo);

      final done = await _pumpUntilCompleted(tester, cubit.close());

      expect(
        done,
        isTrue,
        reason: 'close() during initial load never completed',
      );
      expect(cubit.isClosed, isTrue);
    });

    testWidgets('RoomCubit.close can be called twice', (tester) async {
      final cubit = roomCubitForTest(repo);
      final first = await _pumpUntilCompleted(tester, cubit.close());
      expect(first, isTrue, reason: 'first close() never completed');

      final second = await _pumpUntilCompleted(tester, cubit.close());

      expect(second, isTrue, reason: 'second close() never completed');
    });

    testWidgets(
      'ThreadHostCubit.close closes its hosted room under a fake clock',
      (tester) async {
        final host = hostForTest();
        unawaited(host.select(generalThread()));
        await _pumpUntilDone(tester, () => host.roomCubit != null);
        final room = host.roomCubit;
        expect(
          room,
          isNotNull,
          reason: 'select() never created the room cubit',
        );

        final done = await _pumpUntilCompleted(tester, host.close());

        expect(done, isTrue, reason: 'host close() future never completed');
        expect(room!.isClosed, isTrue);
        expect(host.isClosed, isTrue);
      },
    );

    testWidgets('ThreadHostCubit.close can be called twice', (tester) async {
      final host = hostForTest();
      unawaited(host.select(generalThread()));
      await _pumpUntilDone(tester, () => host.roomCubit != null);
      expect(
        host.roomCubit,
        isNotNull,
        reason: 'select() never created the room cubit',
      );
      final first = await _pumpUntilCompleted(tester, host.close());
      expect(first, isTrue, reason: 'first host close() never completed');

      final second = await _pumpUntilCompleted(tester, host.close());

      expect(second, isTrue, reason: 'second host close() never completed');
    });
  });
}

/// Pumps fake time in small steps until [future] resolves or the bound is hit.
Future<bool> _pumpUntilCompleted(
  WidgetTester tester,
  Future<void> future,
) async {
  var done = false;
  Object? error;
  StackTrace? stack;
  unawaited(
    future.then(
      (_) => done = true,
      onError: (Object e, StackTrace st) {
        error = e;
        stack = st;
      },
    ),
  );
  for (var i = 0; i < 200 && !done && error == null; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  if (error != null) {
    Error.throwWithStackTrace(error!, stack!);
  }
  return done;
}

Future<void> _pumpUntilDone(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200 && !ready(); i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}
