import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_lobby/domain/entity/beacon_lobby.dart';
import 'package:tentura/features/beacon_threads/domain/coordination_item_room_sync.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../support/burst_coalescer_test_timing.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

class _SnapshotRepository extends FakeBeaconThreadsRepository {
  _SnapshotRepository() : super(userId: kRoomCubitFakeMyUserId);

  int fetchRoomStateCalls = 0;
  String currentLine = '';
  final fetchedThreadItemIds = <String?>[];

  @override
  Future<List<RoomMessage>> fetchMessages({
    required String beaconId,
    String? beforeIso,
    String? threadItemId,
  }) {
    fetchedThreadItemIds.add(threadItemId);
    return super.fetchMessages(
      beaconId: beaconId,
      beforeIso: beforeIso,
      threadItemId: threadItemId,
    );
  }

  @override
  Future<BeaconRoomState> fetchBeaconRoomState(String beaconId) async {
    fetchRoomStateCalls++;
    return BeaconRoomState(
      beaconId: beaconId,
      updatedAt: DateTime.utc(2026),
      currentLine: currentLine,
    );
  }
}

void main() {
  group('RoomCubit coalesces a room hint burst', () {
    for (final questions in [false, true]) {
      test(
        questions
            ? 'Questions shows fresh messages with one scoped read per burst'
            : 'discussion shows fresh messages and room state with one read each per burst',
        () {
          fakeAsync((async) {
            registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
            final repo = _SnapshotRepository();
            addTearDown(repo.dispose);
            final threadItemId = questions ? 'request-questions' : null;
            final cubit = RoomCubit(
              beaconId: kRoomCubitFakeBeaconId,
              threadItemId: threadItemId,
              lobbyAccess: questions
                  ? const BeaconLobbyAccess(canRead: true, canPost: true)
                  : null,
              beaconRoomCase: roomCubitMakeCase(repo),
              coordinationItemRoomSync: CoordinationItemRoomSync(),
              presenceRepository: roomCubitFakePresenceRepository(),
              effects: FakeUiEffectPort(),
            );
            addTearDown(cubit.close);
            async.flushMicrotasks();
            expect(cubit.state.status, isA<StateIsSuccess>());
            expect(cubit.state.messages, isEmpty);
            final messagesAfterLoad = repo.fetchMessagesCallCount;
            final roomStateAfterLoad = repo.fetchRoomStateCalls;
            repo.fetchedThreadItemIds.clear();

            final gate = Completer<void>();
            repo
              ..messages = [
                RoomMessage(
                  id: 'fresh-message',
                  beaconId: kRoomCubitFakeBeaconId,
                  threadItemId: threadItemId,
                  authorId: 'peer',
                  body: 'The meeting starts at noon',
                  createdAt: DateTime.utc(2026),
                ),
              ]
              ..currentLine = 'Meet at noon'
              ..fetchMessagesCompleter = gate
              // One delivery turn, as when the invalidation buffer flushes.
              ..emitInvalidation(BeaconRoomEntityType.participant)
              ..emitInvalidation(BeaconRoomEntityType.helpOffer)
              ..emitInvalidation(BeaconRoomEntityType.coordinationItem);
            // Let the coalesced refresh start while the snapshot remains in flight.
            elapseAfterHintBurst(async);
            expect(repo.fetchMessagesCallCount - messagesAfterLoad, 1);
            expect(gate.isCompleted, isFalse);
            expect(repo.fetchRoomStateCalls - roomStateAfterLoad, 0);
            expect(cubit.state.messages, isEmpty);

            gate.complete();
            async.flushMicrotasks();
            elapseAfterHintBurst(async);

            expect(cubit.state.loadError, isNull);
            expect(cubit.state.messages.single.id, 'fresh-message');
            expect(
              cubit.state.messages.single.body,
              'The meeting starts at noon',
            );
            expect(
              {
                'message reads':
                    repo.fetchMessagesCallCount - messagesAfterLoad,
                'room-state reads':
                    repo.fetchRoomStateCalls - roomStateAfterLoad,
              },
              {'message reads': 1, 'room-state reads': questions ? 0 : 1},
              reason: 'hints delivered together are covered by one snapshot',
            );
            expect(repo.fetchedThreadItemIds, [threadItemId]);
            if (questions) {
              expect(cubit.state.roomState, isNull);
            } else {
              expect(cubit.state.roomState?.currentLine, 'Meet at noon');
            }
          });
        },
      );
    }
  });
}
