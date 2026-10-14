import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_display_status_dto.dart';
import 'package:tentura/domain/entity/beacon_room_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/beacon_view/ui/util/beacon_hud_derivation.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

/// B079 — a background refresh of the request fetches about ten slices at
/// once. When one of the slices that is not guarded (display status, inbox
/// context, help offers) failed, for example with a "Constellation database
/// busy" answer, the whole refresh was dropped, including a room state that
/// had arrived with the new next step, so members kept an old next step until
/// a reload.
class _DisplayStatusFailingAfterFirstLoad extends FakeBeaconDisplayRepository {

  var _calls = 0;

  @override
  Future<List<BeaconDisplayStatusDto>> fetchDisplayStatuses(
    List<String> beaconIds,
  ) async {
    _calls++;
    if (_calls > 1) throw Exception('Constellation database busy');
    return super.fetchDisplayStatuses(beaconIds);
  }
}

void main() {
  setUpAll(() async {
    await initializeDateFormatting('en');
  });

  const myProfile = Profile(id: 'Uhelper', displayName: 'Helper');
  const beaconId = 'B079now';
  final l10n = lookupL10n(const Locale('en'));

  Beacon readableBeacon({DateTime? updatedAt}) => Beacon(
    id: beaconId,
    title: 'Moving day',
    createdAt: DateTime.utc(2026, 10, 14),
    updatedAt: updatedAt ?? DateTime.utc(2026, 10, 14),
    author: const Profile(id: 'Uauthor', displayName: 'Author'),
  );

  BeaconRoomState roomWithLine(String line) => BeaconRoomState(
    beaconId: beaconId,
    updatedAt: DateTime.utc(2026, 10, 14, 9),
    currentLine: line,
  );

  test(
    'a new next step is shown even when another slice of the refresh fails',
    () async {
      final room = FakeBeaconViewRoomRepository(roomState: roomWithLine('v1'));
      addTearDown(room.dispose);
      var beacon = readableBeacon();
      final beaconRepo = TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => beacon;
      addTearDown(beaconRepo.dispose);
      final effects = FakeUiEffectPort();
      final cubit = BeaconViewCubit(
        id: beaconId,
        myProfile: myProfile,
        beaconViewCase: buildTestBeaconViewCase(
          beaconRepo: beaconRepo,
          roomRepo: room,
          displayRepo: _DisplayStatusFailingAfterFirstLoad(),
        ),
        effects: effects,
      );
      addTearDown(cubit.close);
      await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
      expect(beaconHudNowLine(l10n, cubit.state), 'v1');
      final fetchesAfterLoad = room.fetchBeaconRoomStateCalls;

      // The author saves a new next step; the server pushes a beacon update.
      room.roomState = roomWithLine('v2');
      beacon = readableBeacon(updatedAt: DateTime.utc(2026, 10, 14, 9, 5));
      beaconRepo.emitUpdate(beacon);
      await pumpUntil(
        cubit.stream,
        () => room.fetchBeaconRoomStateCalls > fetchesAfterLoad,
      );
      await Future<void>.delayed(const Duration(milliseconds: 150));

      expect(cubit.state.beaconRoomCue?.currentLine, 'v2');
      expect(beaconHudNowLine(l10n, cubit.state), 'v2');
      expect(effects.emitted, isEmpty);
    },
  );
}
