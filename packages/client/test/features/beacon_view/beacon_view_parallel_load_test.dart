import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_coordination_phase.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/beacon_fact_card.dart';
import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_provenance.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

/// The first load reads its slices in parallel. These tests pin what the
/// screen gets from that read: each slice lands in its own state field, and
/// when slices fail the viewer gets one error, the one that came first in
/// time (not the first in the list), as the original exception object.

const _beaconId = 'BparallelLoad';
const _viewer = Profile(id: 'Uviewer', displayName: 'Viewer');

final class _InboxBoom implements Exception {
  const _InboxBoom();
}

final class _DisplayBoom implements Exception {
  const _DisplayBoom();
}

class _FailingInboxRepository extends FakeBeaconViewInboxRepository {
  _FailingInboxRepository(this.delay);

  final Duration delay;

  @override
  Future<
    ({
      InboxItemStatus? status,
      InboxProvenance provenance,
      String latestNotePreview,
    })
  >
  fetchInboxContextForBeacon(String beaconId) async {
    await Future<void>.delayed(delay);
    throw const _InboxBoom();
  }
}

class _FailingDisplayRepository extends FakeBeaconDisplayRepository {
  _FailingDisplayRepository(this.delay);

  final Duration delay;

  @override
  Future<List<BeaconDisplayStatusDto>> fetchDisplayStatuses(
    List<String> beaconIds,
  ) async {
    await Future<void>.delayed(delay);
    throw const _DisplayBoom();
  }
}

Beacon _beacon() => Beacon(
  id: _beaconId,
  title: 'Parallel load',
  author: const Profile(id: 'Uauthor', displayName: 'Author'),
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
);

void main() {
  late FakeUiEffectPort effects;

  BeaconViewCubit buildCubit({
    FakeBeaconViewInboxRepository? inboxRepo,
    FakeBeaconDisplayRepository? displayRepo,
    FakeBeaconViewFactCardRepository? factCardsRepo,
    FakeBeaconViewRoomRepository? roomRepo,
  }) {
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => _beacon();
    addTearDown(beaconRepo.dispose);
    final cubit = BeaconViewCubit(
      id: _beaconId,
      myProfile: _viewer,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        inboxRepo: inboxRepo,
        displayRepo: displayRepo,
        factCardsRepo: factCardsRepo,
        roomRepo: roomRepo,
      ),
      effects: effects = FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    return cubit;
  }

  // The Request itself is already on screen when the slices fail, so the
  // failure reaches the viewer as one error snack carrying the error.
  Future<Object?> failedLoadError(BeaconViewCubit cubit) async {
    await pumpUntilEffects(
      () => effects.emitted.whereType<ShowError>().isNotEmpty,
    );
    // Let a second failure, if any, land before reading.
    await Future<void>.delayed(const Duration(milliseconds: 150));
    final errors = effects.emitted.whereType<ShowError>().toList();
    expect(errors, hasLength(1));
    return errors.single.error;
  }

  test(
    'one failing slice fails the first load with its own error snack',
    () async {
      final cubit = buildCubit(
        inboxRepo: _FailingInboxRepository(Duration.zero),
      );

      final error = await failedLoadError(cubit);

      expect(error, isA<_InboxBoom>());
      expect(error, isNot(isA<ParallelWaitError<Object?, Object?>>()));
      expect(cubit.state.beaconContextLoaded, isFalse);
      expect(cubit.state.beacon.id, _beaconId);
    },
  );

  test('two failing slices: the error that came first in time wins '
      '(later slice in the list fails first)', () async {
    final cubit = buildCubit(
      inboxRepo: _FailingInboxRepository(const Duration(milliseconds: 80)),
      displayRepo: _FailingDisplayRepository(Duration.zero),
    );

    expect(await failedLoadError(cubit), isA<_DisplayBoom>());
  });

  test('two failing slices: the error that came first in time wins '
      '(earlier slice in the list fails first)', () async {
    final cubit = buildCubit(
      inboxRepo: _FailingInboxRepository(Duration.zero),
      displayRepo: _FailingDisplayRepository(const Duration(milliseconds: 80)),
    );

    expect(await failedLoadError(cubit), isA<_InboxBoom>());
  });

  test('each slice of the read lands in its own state field', () async {
    final fact = BeaconFactCard(
      id: 'fact-parallel-1',
      beaconId: _beaconId,
      factText: 'Gate code is 4821',
      visibility: BeaconFactCardVisibilityBits.public,
      pinnedBy: 'Uauthor',
      pinnedByTitle: 'Author',
      createdAt: DateTime.utc(2026, 7),
      status: BeaconFactCardStatusBits.active,
    );
    const display = BeaconDisplayStatusDto(
      beaconId: _beaconId,
      status: BeaconStatus.open,
      phase: BeaconCoordinationPhase.lookingForHelpers,
      suggestedAction: BeaconPhasePrimaryAction.offerHelp,
      slot2Kind: BeaconPhaseSlot2Kind.noOffersYet,
      tier: BeaconDisplayTier.coordination,
    );
    final room = FakeBeaconViewRoomRepository(
      roomState: BeaconRoomState(
        beaconId: _beaconId,
        updatedAt: DateTime.utc(2026, 7, 1, 9),
        currentLine: 'Bring the van at nine',
      ),
    );
    addTearDown(room.dispose);
    final cubit = buildCubit(
      inboxRepo: FakeBeaconViewInboxRepository(
        status: InboxItemStatus.watching,
      ),
      displayRepo: FakeBeaconDisplayRepository(rows: const [display]),
      factCardsRepo: FakeBeaconViewFactCardRepository(cards: [fact]),
      roomRepo: room,
    );

    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);

    final state = cubit.state;
    expect(state.inboxStatus, InboxItemStatus.watching);
    expect(state.factCards.map((c) => c.id), ['fact-parallel-1']);
    expect(state.displayStatus, display);
    expect(state.beaconRoomCue?.currentLine, 'Bring the van at nine');
    expect(state.roomParticipantsLoaded, isTrue);
    expect(state.roomActivityEvents, isEmpty);
    expect(state.teamAcquaintanceIds, isEmpty);
    expect(state.closureState, isNull);
  });
}
