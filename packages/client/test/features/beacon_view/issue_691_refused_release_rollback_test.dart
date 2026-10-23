import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

const _author = Profile(id: 'Uauthor691', displayName: 'Author');
const _helper = Profile(id: 'Uhelper691', displayName: 'Helper');
const _beaconId = 'B691release';
final _t = DateTime.utc(2026, 10, 20);

/// The server refuses the release: Close won the race (`beaconNotOpen`).
class _RefusingCoordinationRepository
    extends FakeBeaconViewCoordinationRepository {
  int releaseCalls = 0;

  /// When set, the refusal waits for it (the request is in flight).
  Future<void>? gate;

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> releaseCommitment({
    required String beaconId,
    required String offerUserId,
    required String reason,
  }) async {
    releaseCalls++;
    await gate;
    throw Exception('beaconNotOpen');
  }

  int removeCalls = 0;

  @override
  Future<({BeaconStatus status, DateTime? updatedAt})> removeFromRoom({
    required String beaconId,
    required String offerUserId,
    required String reason,
  }) async {
    removeCalls++;
    throw Exception('beaconNotOpen');
  }
}

/// Records what the People tab showed at the moment the error surfaced.
class _SnapshotEffectPort extends FakeUiEffectPort {
  void Function(UiEffect effect)? onEmit;

  @override
  void emit(UiEffect effect) {
    onEmit?.call(effect);
    super.emit(effect);
  }
}

TimelineHelpOffer _acknowledgedOffer() => TimelineHelpOffer(
  user: _helper,
  message: 'I can bring a van',
  createdAt: _t,
  updatedAt: _t,
  roomAccess: RoomAccessBits.admitted,
  stakeState: CommitmentStakeState.acknowledged,
);

BeaconParticipant _helperParticipant() => BeaconParticipant(
  id: 'p-h691',
  beaconId: _beaconId,
  userId: _helper.id,
  role: BeaconParticipantRoleBits.helper,
  status: BeaconParticipantStatusBits.committed,
  roomAccess: RoomAccessBits.admitted,
  createdAt: _t,
  updatedAt: _t,
);

/// GitHub #691: Close and «End participation» at the same moment — Close
/// wins, the server refuses the release, and the People tab must not keep
/// showing «Participation ended» until a reload.
void main() {
  late TrackingBeaconRepository beaconRepo;
  late _RefusingCoordinationRepository coordinationRepo;
  late _SnapshotEffectPort effects;
  late BeaconViewCubit cubit;
  late Completer<Beacon> hangingRefetch;

  setUp(() async {
    hangingRefetch = Completer<Beacon>();
    beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (_) async => Beacon(
        id: _beaconId,
        title: 'Moving day',
        createdAt: _t,
        updatedAt: _t,
        status: BeaconStatus.open,
        canReadContent: true,
        author: _author,
      );
    coordinationRepo = _RefusingCoordinationRepository();
    effects = _SnapshotEffectPort();
    cubit = BeaconViewCubit(
      id: _beaconId,
      myProfile: _author,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        coordinationRepo: coordinationRepo,
      ),
      effects: effects,
    );
    addTearDown(() async {
      await cubit.close();
      await beaconRepo.dispose();
    });
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
    await pumpEventQueue();
    // ignore: invalid_use_of_protected_member -- seeds the People tab.
    cubit.emit(
      cubit.state.copyWith(
        helpOffers: [_acknowledgedOffer()],
        roomParticipants: [_helperParticipant()],
      ),
    );
    // From here on the refresh read never answers (slow network).
    beaconRepo.fetchByIdHandler = (_) => hangingRefetch.future;
  });

  group('Issue #691 refused release rolls back', () {
    test(
      'a refused release restores the helper and shows an error even when '
      'the refresh never answers',
      () async {
        var finished = false;
        Object? leaked;
        unawaited(
          cubit
              .releaseCommitment(offerUserId: _helper.id, reason: 'Too late')
              .then<void>(
                (_) {
                  finished = true;
                },
                onError: (Object e) {
                  leaked = e;
                },
              ),
        );
        await pumpEventQueue();

        expect(coordinationRepo.releaseCalls, 1);
        final offer = cubit.state.helpOffers.single;
        expect(offer.stakeState, CommitmentStakeState.acknowledged);
        expect(offer.roomAccess, RoomAccessBits.admitted);
        expect(offer.lastRemoveReason, isNull);
        expect(
          cubit.state.roomParticipants.single.roomAccess,
          RoomAccessBits.admitted,
        );
        expect(effects.emitted.whereType<ShowError>(), hasLength(1));
        expect(
          finished,
          isTrue,
          reason: 'the release call must not wait on the refresh',
        );
        expect(leaked, isNull, reason: 'the People tab caller has no catch');
      },
    );

    test('the helper is restored before the error surfaces', () async {
      CommitmentStakeState? shownWithError;
      effects.onEmit = (effect) {
        if (effect is ShowError) {
          shownWithError = cubit.state.helpOffers.single.stakeState;
        }
      };

      unawaited(
        cubit
            .releaseCommitment(offerUserId: _helper.id, reason: 'Too late')
            .catchError((Object _) {}),
      );
      await pumpEventQueue();

      expect(shownWithError, CommitmentStakeState.acknowledged);
    });

    test('a refused release still asks the server for the truth', () async {
      final readsBefore = beaconRepo.fetchByIdCalls;

      unawaited(
        cubit
            .releaseCommitment(offerUserId: _helper.id, reason: 'Too late')
            .catchError((Object _) {}),
      );
      await pumpEventQueue();

      expect(beaconRepo.fetchByIdCalls, greaterThan(readsBefore));
    });

    test(
      'the optimistic update shows while the release is in flight and '
      'rolls back once it is refused',
      () async {
        final gate = Completer<void>();
        coordinationRepo.gate = gate.future;

        unawaited(
          cubit
              .releaseCommitment(offerUserId: _helper.id, reason: 'Done')
              .catchError((Object _) {}),
        );
        await pumpEventQueue();

        expect(
          cubit.state.helpOffers.single.stakeState,
          CommitmentStakeState.released,
        );
        expect(effects.emitted.whereType<ShowError>(), isEmpty);

        gate.complete();
        await pumpEventQueue();

        expect(
          cubit.state.helpOffers.single.stakeState,
          CommitmentStakeState.acknowledged,
        );
      },
    );

    test(
      'a refused remove from the room restores the helper and shows an error '
      'even when the refresh never answers',
      () async {
        var finished = false;
        Object? leaked;
        CommitmentStakeState? shownWithError;
        effects.onEmit = (effect) {
          if (effect is ShowError) {
            shownWithError = cubit.state.helpOffers.single.stakeState;
          }
        };
        unawaited(
          cubit
              .removeFromRoom(offerUserId: _helper.id, reason: 'Too late')
              .then<void>(
                (_) {
                  finished = true;
                },
                onError: (Object e) {
                  leaked = e;
                },
              ),
        );
        await pumpEventQueue();

        expect(coordinationRepo.removeCalls, 1);
        final offer = cubit.state.helpOffers.single;
        expect(offer.roomAccess, RoomAccessBits.admitted);
        expect(offer.admissionAction, isNull);
        expect(offer.lastRemoveReason, isNull);
        expect(
          cubit.state.roomParticipants.single.roomAccess,
          RoomAccessBits.admitted,
        );
        expect(effects.emitted.whereType<ShowError>(), hasLength(1));
        expect(shownWithError, CommitmentStakeState.acknowledged);
        expect(finished, isTrue);
        expect(leaked, isNull);
      },
    );
  });
}
