// tentura-617.26: RoomCubit fact edit with baseRevisionSeq, conflict state,
// fact-list-only invalidation (issue #181, plan §8.7 / §14.5 / §14.6).

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'room_cubit_fakes.dart';

const _kFactId = 'fact-1';

BeaconFactCard _fact({required String text, required int seq}) =>
    BeaconFactCard(
      id: _kFactId,
      beaconId: kRoomCubitFakeBeaconId,
      factText: text,
      visibility: 0,
      pinnedBy: 'pinner',
      createdAt: DateTime.utc(2026),
      status: 0,
      revisionSeq: seq,
    );

/// Records fact-list loads and correct() calls.
class _RecordingFactCardRepository extends FakeBeaconFactCardRepository {
  List<BeaconFactCard> cards = [];
  int listCallCount = 0;
  Exception? correctError;
  int? lastBaseRevisionSeq;
  int correctCallCount = 0;

  /// Applied to [cards] right before [correct] throws [correctError]
  /// (simulates a concurrent edit landing on the server).
  List<BeaconFactCard>? cardsAfterCorrect;

  @override
  Future<List<BeaconFactCard>> list({required String beaconId}) async {
    listCallCount++;
    return List<BeaconFactCard>.of(cards);
  }

  @override
  Future<int> correct({
    required String beaconId,
    required String factCardId,
    required String newText,
    required int baseRevisionSeq,
    String? attachmentsJson,
  }) async {
    correctCallCount++;
    lastBaseRevisionSeq = baseRevisionSeq;
    final after = cardsAfterCorrect;
    if (after != null) cards = after;
    final error = correctError;
    if (error != null) throw error;
    return baseRevisionSeq + 1;
  }
}

BeaconThreadsCase _makeCase(
  FakeBeaconThreadsRepository fakeRoom,
  _RecordingFactCardRepository factRepo,
) => BeaconThreadsCase(
  fakeRoom,
  factRepo,
  FakePollingRepository(),
  FakeBeaconRoomHintsRepository(),
  RoomReadWatermarkStore.testing(),
  buildTestRealtimeSync().case_,
  env: const Env(),
  logger: Logger('test'),
);

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 30));

void main() {
  late FakeBeaconThreadsRepository fakeRoom;
  late _RecordingFactCardRepository factRepo;
  late FakeUiEffectPort effects;
  late RoomCubit cubit;

  Future<void> start() async {
    registerRoomCubitProfileCubit(kRoomCubitFakeMyUserId);
    fakeRoom = FakeBeaconThreadsRepository(userId: kRoomCubitFakeMyUserId);
    addTearDown(fakeRoom.dispose);
    effects = FakeUiEffectPort();
    cubit = roomCubitForTest(
      fakeRoom,
      effects: effects,
      beaconRoomCase: _makeCase(fakeRoom, factRepo),
    );
    addTearDown(cubit.close);
    await awaitRoomCubitLoad(cubit);
    await _settle();
  }

  setUp(() {
    factRepo = _RecordingFactCardRepository()
      ..cards = [_fact(text: 'original', seq: 3)];
  });

  group('RoomCubit.correctFact (tentura-617.26)', () {
    test(
      'passes the revisionSeq of the card the edit sheet opened with, '
      'not the one in state after an RT refresh',
      () async {
        await start();
        final openedWith = cubit.state.factCards.single;
        expect(openedWith.revisionSeq, 3);

        // A concurrent edit lands via RT while the sheet is open.
        factRepo.cards = [_fact(text: 'someone else', seq: 4)];
        fakeRoom.emitInvalidation(BeaconRoomEntityType.factCard);
        await _settle();
        expect(cubit.state.factCards.single.revisionSeq, 4);

        await cubit.correctFact(
          factCardId: openedWith.id,
          newText: 'my edit',
          baseRevisionSeq: openedWith.revisionSeq,
        );

        expect(factRepo.correctCallCount, 1);
        expect(factRepo.lastBaseRevisionSeq, 3);
      },
    );

    test(
      'conflict refreshes only the fact list and emits factEditConflict '
      'with the refreshed current text',
      () async {
        await start();
        final listBefore = factRepo.listCallCount;
        final messagesBefore = fakeRoom.fetchMessagesCallCount;
        factRepo
          ..cardsAfterCorrect = [_fact(text: 'server text', seq: 5)]
          ..correctError = const BeaconFactEditConflictException(
            currentSeq: 5,
          );

        await cubit.correctFact(
          factCardId: _kFactId,
          newText: 'my edit',
          baseRevisionSeq: 3,
        );
        await _settle();

        expect(factRepo.listCallCount, listBefore + 1);
        expect(
          fakeRoom.fetchMessagesCallCount,
          messagesBefore,
          reason: 'conflict must not reload the message page',
        );
        final conflict = cubit.state.factEditConflict;
        expect(conflict, isNotNull);
        expect(conflict!.id, _kFactId);
        expect(conflict.factText, 'server text');
        expect(conflict.revisionSeq, 5);
        expect(cubit.state.factCards.single.factText, 'server text');
        expect(
          effects.emitted.whereType<ShowError>(),
          isEmpty,
          reason: 'conflict is a state, not a generic error snack',
        );
      },
    );

    test(
      'success refreshes the fact list without reloading messages',
      () async {
        await start();
        final listBefore = factRepo.listCallCount;
        final messagesBefore = fakeRoom.fetchMessagesCallCount;
        factRepo.cardsAfterCorrect = [_fact(text: 'my edit', seq: 4)];

        await cubit.correctFact(
          factCardId: _kFactId,
          newText: 'my edit',
          baseRevisionSeq: 3,
        );
        await _settle();

        expect(factRepo.listCallCount, listBefore + 1);
        expect(fakeRoom.fetchMessagesCallCount, messagesBefore);
        expect(cubit.state.factCards.single.factText, 'my edit');
        expect(cubit.state.factEditConflict, isNull);
      },
    );

    for (final (name, error) in <(String, Exception)>[
      ('removed', const BeaconFactRemovedException()),
      ('rate-limited', const BeaconFactRateLimitedException()),
    ]) {
      test('$name goes to the existing error path', () async {
        await start();
        factRepo.correctError = error;

        await cubit.correctFact(
          factCardId: _kFactId,
          newText: 'my edit',
          baseRevisionSeq: 3,
        );
        await _settle();

        final errors = effects.emitted.whereType<ShowError>().toList();
        expect(errors, hasLength(1));
        expect(errors.single.error, same(error));
        expect(cubit.state.factEditConflict, isNull);
      });
    }
  });

  group('RoomCubit factCard invalidation (tentura-617.26)', () {
    test(
      'calls the fact-list loader once and not the message-page loader',
      () async {
        await start();
        final listBefore = factRepo.listCallCount;
        final messagesBefore = fakeRoom.fetchMessagesCallCount;
        final participantsBefore = fakeRoom.fetchParticipantsCallCount;
        factRepo.cards = [_fact(text: 'rt edit', seq: 4)];

        fakeRoom.emitInvalidation(BeaconRoomEntityType.factCard);
        await _settle();

        expect(factRepo.listCallCount, listBefore + 1);
        expect(
          fakeRoom.fetchMessagesCallCount,
          messagesBefore,
          reason: 'factCard invalidation must not call load()',
        );
        expect(fakeRoom.fetchParticipantsCallCount, participantsBefore);
        expect(cubit.state.factCards.single.factText, 'rt edit');
      },
    );
  });
}
