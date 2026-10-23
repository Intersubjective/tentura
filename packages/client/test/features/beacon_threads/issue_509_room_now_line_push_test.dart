// #509: the next step («NOW …») is shown in two places that read two
// stores. The Now pane (BeaconViewCubit.beaconRoomCue) refetches on the
// server's push for a next-step edit; the chat's pinned strip
// (RoomCubit.roomState) did not. The server announces a next-step edit only
// as a `beacon` update (BeaconRoomRepository.setBeaconRoomCurrentLine emits
// `emit_realtime_entity_change('beacon', ...)`), and
// BeaconRoomInvalidation.fromRealtimeChange maps `beacon` to null, so the
// room never refetched and the strip kept an older next step than the pane.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

/// Room invalidations come from the shared realtime stream exactly as in
/// `BeaconThreadsRepository` (production): every change goes through
/// `BeaconRoomInvalidation.fromRealtimeChange`. The server's next step is
/// [roomState]; [failRoomState] makes the next room-state fetch fail like a
/// busy database.
class _PushedRoomRepository extends FakeBeaconThreadsRepository {
  _PushedRoomRepository(this._realtime, {required this.roomState})
    : super(userId: kRoomCubitFakeMyUserId);

  final RealtimeSyncCase _realtime;

  BeaconRoomState roomState;

  bool failRoomState = false;

  int fetchRoomStateCalls = 0;

  @override
  Stream<BeaconRoomInvalidation> get beaconRoomInvalidations => _realtime
      .entityChanges
      .map(BeaconRoomInvalidation.fromRealtimeChange)
      .where((invalidation) => invalidation != null)
      .cast<BeaconRoomInvalidation>();

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async {
    fetchRoomStateCalls++;
    if (failRoomState) throw Exception('Constellation database busy');
    return roomState;
  }
}

BeaconRoomState _line(String text, int minute) => BeaconRoomState(
  beaconId: kRoomCubitFakeBeaconId,
  updatedAt: DateTime.utc(2026, 10, 14, 9, minute),
  currentLine: text,
  updatedBy: 'author-509',
);

/// What the server sends after `updateRoomNowLine` (another member's edit):
/// a `beacon` update flagged `room_state` (#654).
RealtimeEntityChange _beaconUpdate(
  String beaconId, {
  bool roomStateChanged = true,
}) => RealtimeEntityChange(
  kind: RealtimeEntityKind.beacon,
  aggregateId: beaconId,
  operation: RealtimeOperation.update,
  source: RealtimeChangeSource.serverInvalidation,
  actorUserId: 'author-509',
  roomStateChanged: roomStateChanged,
);

Future<void> _pumpUntil(bool Function() done) async {
  for (var i = 0; i < 40 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}

void main() {
  group('#509 the chat strip follows a pushed next-step edit', () {
    late TestRealtimeSyncPort port;
    late _PushedRoomRepository repo;
    late FakeUiEffectPort effects;
    late RoomCubit cubit;

    setUp(() async {
      registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
      final realtime = buildTestRealtimeSync();
      port = realtime.port;
      addTearDown(port.dispose);
      repo = _PushedRoomRepository(realtime.case_, roomState: _line('v1', 0));
      effects = FakeUiEffectPort();
      cubit = roomCubitForTest(
        repo,
        effects: effects,
        realtimeSyncCase: realtime.case_,
      );
      addTearDown(cubit.close);
      await awaitRoomCubitLoad(cubit);
      await _pumpUntil(() => cubit.state.roomState != null);
    });

    test('the newest next step reaches the room after the push', () async {
      // Precondition: the room loaded the first next step from the server.
      expect(cubit.state.roomState?.currentLine, 'v1');
      final fetchesAfterLoad = repo.fetchRoomStateCalls;

      // Another member saves v2; the server pushes its `beacon` update.
      repo.roomState = _line('v2', 5);
      port.emitChange(_beaconUpdate(kRoomCubitFakeBeaconId));
      await _pumpUntil(() => cubit.state.roomState?.currentLine == 'v2');

      expect(repo.fetchRoomStateCalls, greaterThan(fetchesAfterLoad));
      expect(cubit.state.roomState?.currentLine, 'v2');
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
    });

    test('six edits in a row: the room ends on the last one', () async {
      for (var v = 2; v <= 6; v++) {
        repo.roomState = _line('v$v', v);
        port.emitChange(_beaconUpdate(kRoomCubitFakeBeaconId));
        await _pumpUntil(() => cubit.state.roomState?.currentLine == 'v$v');
      }

      expect(cubit.state.roomState?.currentLine, 'v6');
    });

    test('a push for another request does not refetch this room', () async {
      final fetchesAfterLoad = repo.fetchRoomStateCalls;
      repo.roomState = _line('v2', 5);

      port.emitChange(_beaconUpdate('some-other-request'));
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(repo.fetchRoomStateCalls, fetchesAfterLoad);
      expect(cubit.state.roomState?.currentLine, 'v1');

      // The same push for this request does refetch (the guard above is
      // not vacuous).
      port.emitChange(_beaconUpdate(kRoomCubitFakeBeaconId));
      await _pumpUntil(() => cubit.state.roomState?.currentLine == 'v2');
      expect(cubit.state.roomState?.currentLine, 'v2');
    });

    // #654: any other request update (title, status, ...) does not refetch
    // the room state.
    test('a beacon update that did not move the next step does not refetch '
        'the room state', () async {
      final fetchesAfterLoad = repo.fetchRoomStateCalls;
      repo.roomState = _line('v2', 5);

      port.emitChange(
        _beaconUpdate(kRoomCubitFakeBeaconId, roomStateChanged: false),
      );
      await Future<void>.delayed(const Duration(milliseconds: 200));

      expect(repo.fetchRoomStateCalls, fetchesAfterLoad);
      expect(cubit.state.roomState?.currentLine, 'v1');
    });

    test('a failed refetch after the push keeps the shown next step', () async {
      final fetchesAfterLoad = repo.fetchRoomStateCalls;
      final messagesBefore = cubit.state.messages;
      repo.failRoomState = true;

      port.emitChange(_beaconUpdate(kRoomCubitFakeBeaconId));
      await _pumpUntil(() => repo.fetchRoomStateCalls > fetchesAfterLoad);
      await Future<void>.delayed(const Duration(milliseconds: 100));

      // The push was acted on ...
      expect(repo.fetchRoomStateCalls, greaterThan(fetchesAfterLoad));
      // ... and a busy server neither blanks the strip nor shows an error
      // for a background refresh.
      expect(cubit.state.roomState?.currentLine, 'v1');
      expect(cubit.state.messages, messagesBefore);
      expect(effects.emitted.whereType<ShowError>(), isEmpty);
    });
  });
}
