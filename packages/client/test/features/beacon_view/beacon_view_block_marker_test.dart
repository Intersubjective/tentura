import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _beaconId = 'Bblockmarker';
const _viewer = Profile(id: 'Ublocked', displayName: 'Priya');

Beacon _request({String title = 'Help me move'}) => Beacon(
  id: _beaconId,
  title: title,
  createdAt: DateTime.utc(2026, 10, 14),
  updatedAt: DateTime.utc(2026, 10, 14),
  author: const Profile(id: 'Ublocker', displayName: 'Tab QA'),
);

RealtimeEntityChange _marker(String aggregateId) => RealtimeEntityChange(
  kind: RealtimeEntityKind.constellationField,
  aggregateId: aggregateId,
  operation: RealtimeOperation.update,
  source: RealtimeChangeSource.serverInvalidation,
);

/// #638: a Request page the blocked person already has open follows the
/// server's block marker instead of waiting for a manual refetch.
void main() {
  late TrackingBeaconRepository repo;
  late ({RealtimeSyncCase case_, TestRealtimeSyncPort port}) realtime;
  late FakeUiEffectPort effects;
  late BeaconViewCubit cubit;
  late Future<Beacon> Function(String id) server;

  setUp(() async {
    server = (_) async => _request();
    repo = TrackingBeaconRepository()..fetchByIdHandler = (id) => server(id);
    realtime = buildTestRealtimeSync();
    effects = FakeUiEffectPort();
    cubit = BeaconViewCubit(
      id: _beaconId,
      myProfile: _viewer,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: repo,
        realtimeSyncCase: realtime.case_,
      ),
      effects: effects,
    );
    addTearDown(() async {
      await cubit.close();
      await realtime.port.dispose();
    });
    await cubit.stream
        .firstWhere((state) => state.beaconContextLoaded)
        .timeout(const Duration(seconds: 2));
  });

  test('a block marker refetches the open Request', () async {
    final reads = repo.fetchByIdCalls;
    server = (_) async => _request(title: 'Help me move (van booked)');

    realtime.port.emitChange(_marker('Ublocker'));
    await cubit.stream
        .firstWhere((s) => s.beacon.title == 'Help me move (van booked)')
        .timeout(const Duration(seconds: 2));

    expect(repo.fetchByIdCalls, greaterThan(reads));
  });

  test('the Request turns unavailable when the block took access away, '
      'with no error bar', () async {
    server = (_) async => throw const BeaconFetchException();

    realtime.port.emitChange(_marker('Ublocker'));
    await cubit.stream
        .firstWhere((s) => s.beaconUnavailable)
        .timeout(const Duration(seconds: 2));

    expect(cubit.state.beaconContentLoaded, isFalse);
    expect(effects.emitted.whereType<ShowError>(), isEmpty);
  });

  // Codex review: a reload that read the Request before the block must not
  // bring the page back after the block's refresh marked it unavailable.
  test(
    'a reload that started before the block does not restore the page',
    () async {
      final staleRead = Completer<Beacon>();
      var reads = 0;
      server = (_) {
        reads++;
        if (reads == 1) return staleRead.future;
        throw const BeaconFetchException();
      };

      // Not gated: runs beside the marker's refresh.
      final reload = cubit.retryInitialLoad();
      realtime.port.emitChange(_marker('Ublocker'));
      await cubit.stream
          .firstWhere((s) => s.beaconUnavailable)
          .timeout(const Duration(seconds: 2));

      staleRead.complete(_request());
      await reload;
      await pumpEventQueue();

      expect(cubit.state.beaconUnavailable, isTrue);
      expect(cubit.state.beaconContentLoaded, isFalse);
    },
  );

  test('an ordinary refresh that cannot read the Request keeps the page '
      '(busy read, not a block)', () async {
    server = (_) async => throw const BeaconFetchException();

    realtime.port.emitCatchUp();
    // Room for the read and its 300 ms retry.
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await pumpEventQueue();

    expect(cubit.state.beaconUnavailable, isFalse);
    expect(cubit.state.beaconContentLoaded, isTrue);
  });

  test('the global constellation marker does not refetch', () async {
    final reads = repo.fetchByIdCalls;

    realtime.port.emitChange(
      _marker(RealtimeSyncCase.globalConstellationFieldId),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await pumpEventQueue();

    expect(repo.fetchByIdCalls, reads);
  });
}
