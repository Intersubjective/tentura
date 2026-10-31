// Typing indicator in a Request's discussion (#766), the cubit half.
//
// Contract these tests pin (the names the implementation is expected to use):
//
// * `RoomTypingSignal({beaconId, userId, typing})`
//   (`features/beacon_threads/domain/entity/room_typing_signal.dart`): one
//   "<user> started / stopped typing" fact the server relayed.
// * `BeaconThreadsRepository` (and so `BeaconThreadsCase`):
//   `Stream<RoomTypingSignal> get roomTypingSignals` and
//   `void sendRoomTyping({required String beaconId, required bool typing})`.
// * `RoomCubit.composerTextChanged(String text)`: the composer reports its
//   current text on every edit. The cubit decides what goes on the wire.
// * `RoomState.typingUserIds` (`List<String>`, in the order people began
//   typing): who is typing now, never the viewer.
//
// No timing knob is part of the contract: the cubit is built the ordinary way
// and the tests wait out its real intervals. The product limits they rely on
// are the server's (packages/server .../websocket_path_room_typing.dart): it
// relays one intent per sender per 3 s and announces a silent typist as
// stopped after 6 s. So a viewer who keeps typing must refresh inside that
// window and no more often than about once a second, and a received "typing"
// must outlive one refresh period yet be gone well before the viewer could be
// misled for long when a stop frame was lost.

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';

import '../../support/test_realtime_sync.dart';
import 'room_cubit_fakes.dart';
import 'support/room_typing_fake_repository.dart';

const _ben = 'user-ben';
const _cara = 'user-cara';

Future<void> _waitUntil(
  bool Function() done, {
  Duration timeout = const Duration(seconds: 5),
  String? reason,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!done()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('${reason ?? 'condition'} not met within $timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 60));

void main() {
  group('RoomCubit typing indicator', () {
    late RoomTypingFakeRepository repo;
    late TestRealtimeSyncPort port;
    late RoomCubit cubit;

    setUp(() async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      repo = RoomTypingFakeRepository();
      final realtime = buildTestRealtimeSync();
      port = realtime.port;
      addTearDown(port.dispose);
      cubit = roomCubitForTest(repo, realtimeSyncCase: realtime.case_);
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
    });

    group('names shown from received intents', () {
      test('nobody is typing in a freshly opened room', () {
        expect(cubit.state.typingUserIds, isEmpty);
      });

      test('a member who starts typing is added', () async {
        repo.relay(_ben);
        await _waitUntil(() => cubit.state.typingUserIds.isNotEmpty);

        expect(cubit.state.typingUserIds, [_ben]);
      });

      test('a second typist is added after the first, once each', () async {
        repo
          ..relay(_ben)
          ..relay(_cara)
          ..relay(_ben);
        await _waitUntil(() => cubit.state.typingUserIds.length == 2);
        await _settle();

        expect(cubit.state.typingUserIds, [_ben, _cara]);
      });

      test('an explicit stop removes only that member', () async {
        repo
          ..relay(_ben)
          ..relay(_cara);
        await _waitUntil(() => cubit.state.typingUserIds.length == 2);

        repo.relay(_ben, typing: false);
        await _waitUntil(() => cubit.state.typingUserIds.length == 1);

        expect(cubit.state.typingUserIds, [_cara]);
      });

      test('a stop from someone who was not typing changes nothing', () async {
        repo
          ..relay(_cara, typing: false)
          ..relay(_ben);
        await _waitUntil(() => cubit.state.typingUserIds.isNotEmpty);
        await _settle();

        expect(cubit.state.typingUserIds, [_ben]);
      });

      test('the viewer is never listed as typing', () async {
        repo
          ..relay(kRoomCubitFakeMyUserId)
          ..relay(_ben);
        await _waitUntil(() => cubit.state.typingUserIds.isNotEmpty);
        await _settle();

        expect(cubit.state.typingUserIds, [_ben]);
      });

      test('typing in another request is ignored', () async {
        repo
          ..relay(_cara, beaconId: 'some-other-request')
          ..relay(_ben);
        await _waitUntil(() => cubit.state.typingUserIds.isNotEmpty);
        await _settle();

        expect(cubit.state.typingUserIds, [_ben]);
      });

      test('a reconnect catch-up forgets everyone who was typing', () async {
        repo.relay(_ben);
        await _waitUntil(() => cubit.state.typingUserIds.isNotEmpty);

        // Intents sent while the socket was down are lost: a stale name
        // would stay until its expiry, so the list restarts empty.
        port.emitCatchUp();
        await _waitUntil(() => cubit.state.typingUserIds.isEmpty);

        expect(cubit.state.typingUserIds, isEmpty);
      });
    });

    group('expiry of received intents', () {
      test(
        'a typist whose stop never arrives is dropped, but not before the '
        'next refresh could have come',
        () async {
          repo.relay(_ben);
          await _waitUntil(() => cubit.state.typingUserIds.isNotEmpty);

          // A typist refreshes every ~3 s, so the name outlives that.
          await Future<void>.delayed(const Duration(milliseconds: 2500));
          expect(
            cubit.state.typingUserIds,
            [_ben],
            reason: 'dropped before a refresh was due',
          );

          // The server itself announces a stop after 6 s; a lost stop frame
          // must not leave the name up much longer than that.
          await _waitUntil(
            () => cubit.state.typingUserIds.isEmpty,
            timeout: const Duration(seconds: 12),
            reason: 'the name expiring',
          );
        },
        timeout: const Timeout(Duration(seconds: 40)),
      );

      test(
        'refreshes keep a typist listed past what a single intent would last',
        () async {
          repo.relay(_ben);
          await _waitUntil(() => cubit.state.typingUserIds.isNotEmpty);

          // Three refreshes, 3 s apart: 9 s in total, more than one intent
          // alone can keep the name.
          for (var i = 0; i < 3; i++) {
            await Future<void>.delayed(const Duration(seconds: 3));
            repo.relay(_ben);
            await _settle();
            expect(
              cubit.state.typingUserIds,
              [_ben],
              reason: 'refresh ${i + 1} must keep the typist listed',
            );
          }

          // Once the refreshes stop, the expiry applies again.
          await _waitUntil(
            () => cubit.state.typingUserIds.isEmpty,
            timeout: const Duration(seconds: 12),
            reason: 'the name expiring after the last refresh',
          );
        },
        timeout: const Timeout(Duration(seconds: 40)),
      );
    });

    group('intents sent while the viewer types', () {
      test('the first keystroke announces typing at once', () async {
        cubit.composerTextChanged('h');
        await _settle();

        expect(repo.intents, [true]);
        expect(repo.intentBeaconIds, [kRoomCubitFakeBeaconId]);
      });

      test('a burst of keystrokes is throttled to one intent', () async {
        ['h', 'he', 'hel', 'hell', 'hello'].forEach(
          cubit.composerTextChanged,
        );
        await _settle();

        expect(repo.intents, [true]);
      });

      test(
        'continuous typing is refreshed inside the server window, not spammed',
        () async {
          // One keystroke every 250 ms for 6.5 s: longer than the server's
          // 6 s expiry, so a typist who is still typing needs a refresh.
          final started = DateTime.now();
          final text = StringBuffer();
          while (DateTime.now().difference(started) <
              const Duration(milliseconds: 6500)) {
            text.write('x');
            cubit.composerTextChanged(text.toString());
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }

          final starts = [
            for (var i = 0; i < repo.intents.length; i++)
              if (repo.intents[i]) repo.intentTimes[i],
          ];
          expect(
            starts.length,
            greaterThanOrEqualTo(2),
            reason: 'a refresh is needed before the server expires the typist',
          );
          for (var i = 1; i < starts.length; i++) {
            final gap = starts[i].difference(starts[i - 1]);
            expect(
              gap,
              greaterThanOrEqualTo(const Duration(milliseconds: 900)),
              reason: 'intents must be throttled, not one per keystroke',
            );
            expect(
              gap,
              lessThanOrEqualTo(const Duration(milliseconds: 5500)),
              reason: 'a refresh must land before the 6 s server expiry',
            );
          }
          expect(
            repo.intents.every((typing) => typing),
            isTrue,
            reason: 'no stop while the text is still being edited',
          );
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test(
        'nothing more is sent once the viewer stops editing',
        () async {
          cubit.composerTextChanged('h');
          // The text stays in the composer, untouched, for longer than the
          // refresh period.
          await Future<void>.delayed(const Duration(seconds: 4));

          expect(
            repo.intents,
            [true],
            reason:
                'no keystrokes, no refresh: the server expires the typist '
                'on its own',
          );
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );

      test('clearing the composer stops typing at once', () async {
        cubit
          ..composerTextChanged('h')
          ..composerTextChanged('');
        await _settle();

        expect(
          repo.intents,
          [true, false],
          reason: 'a stop is never throttled',
        );
      });

      test('a composer that was never typed in sends nothing', () async {
        cubit
          ..composerTextChanged('')
          ..composerTextChanged('   ');
        await _settle();

        expect(repo.intents, isEmpty);
      });

      test('a send stops typing', () async {
        cubit.composerTextChanged('hello');
        expect(await cubit.sendMessage(body: 'hello'), isTrue);
        await _settle();

        expect(repo.intents, [true, false]);
      });

      test(
        'typing again after a stop announces typing again at once',
        () async {
          cubit
            ..composerTextChanged('a')
            ..composerTextChanged('')
            ..composerTextChanged('b');
          await _settle();

          expect(repo.intents, [true, false, true]);
        },
      );

      test('leaving the room while typing stops typing', () async {
        cubit.composerTextChanged('half a thought');
        await cubit.close();

        expect(repo.intents, [true, false]);
      });

      test('a room that is read-only sends no typing intents', () async {
        cubit
          ..syncBeaconStatus(BeaconStatus.closed)
          ..composerTextChanged('too late');
        await _settle();

        expect(repo.intents, isEmpty);
      });
    });
  });
}
