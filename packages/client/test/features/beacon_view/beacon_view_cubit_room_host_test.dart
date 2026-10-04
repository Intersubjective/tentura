import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_response_type.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_state.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
const _beaconId = 'Broomhost001';
const _author = Profile(id: 'Uauthor', displayName: 'Author');

void main() {
  group('BeaconViewCubit as a RoomHost', () {
    late TrackingBeaconRepository beaconRepo;
    late FakeBeaconViewRoomRepository room;
    late BeaconViewCubit cubit;

    setUp(() {
      beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => Beacon(
          id: _beaconId,
          title: 'Room host beacon',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          status: BeaconStatus.open,
          canReadContent: true,
          author: _author,
        );
      room = FakeBeaconViewRoomRepository();
      cubit = BeaconViewCubit(
        id: _beaconId,
        myProfile: _myProfile,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          roomRepo: room,
          factCardsRepo: FakeBeaconViewFactCardRepository(),
        ),
        effects: FakeUiEffectPort(),
      );
      addTearDown(() async {
        await cubit.close();
        await beaconRepo.dispose();
        await room.dispose();
      });
    });

    test('implements RoomHost with Request capabilities and its beacon id', () {
      expect(cubit, isA<RoomHost>());
      final host = cubit as RoomHost;
      expect(host.beaconId, _beaconId);
      expect(host.capabilities, const RoomCapabilities.request());
    });

    test('exposes the loaded author and status from state', () async {
      await _loaded(cubit);
      final host = cubit as RoomHost;
      expect(host.author.id, _author.id);
      expect(host.status, BeaconStatus.open);
    });

    test('changes emits once per subsequent state change', () async {
      await _loaded(cubit);
      await pumpEventQueue();
      final host = cubit as RoomHost;
      var events = 0;
      final sub = host.changes.listen((_) => events++);
      addTearDown(sub.cancel);

      // ignore: invalid_use_of_protected_member -- drives a state transition.
      cubit.emit(cubit.state.copyWith(isHelpOffered: true));
      await pumpEventQueue();

      expect(events, 1);
    });

    test('admission getters follow the viewer help-offer state', () async {
      await _loaded(cubit);
      await pumpEventQueue();
      final host = cubit as RoomHost;
      expect(host.isAdmissionBlocked, isFalse);
      expect(host.coordinationDeniesAdmission, isFalse);

      // ignore: invalid_use_of_protected_member -- drives a state transition.
      cubit.emit(
        cubit.state.copyWith(
          isHelpOffered: true,
          helpOffers: [_myOffer()],
        ),
      );
      expect(host.isAdmissionBlocked, isTrue);
      expect(host.coordinationDeniesAdmission, isFalse);

      // ignore: invalid_use_of_protected_member -- drives a state transition.
      cubit.emit(
        cubit.state.copyWith(
          helpOffers: [
            _myOffer(response: CoordinationResponseType.notSuitable),
          ],
        ),
      );
      expect(host.isAdmissionBlocked, isTrue);
      expect(host.coordinationDeniesAdmission, isTrue);

      // ignore: invalid_use_of_protected_member -- drives a state transition.
      cubit.emit(
        cubit.state.copyWith(
          helpOffers: [
            _myOffer(response: CoordinationResponseType.useful),
          ],
        ),
      );
      expect(host.isAdmissionBlocked, isFalse);
      expect(host.coordinationDeniesAdmission, isFalse);
    });
  });
}

TimelineHelpOffer _myOffer({CoordinationResponseType? response}) =>
    TimelineHelpOffer(
      user: _myProfile,
      message: '',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
      coordinationResponse: response,
    );

Future<void> _loaded(BeaconViewCubit cubit) async {
  if (cubit.state.beaconContextLoaded) return;
  await cubit.stream
      .timeout(const Duration(seconds: 2))
      .firstWhere((s) => s.beaconContextLoaded);
}
