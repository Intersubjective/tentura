import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon/domain/exception.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _viewer = Profile(id: 'Uviewer', displayName: 'Viewer');
const _beaconId = 'Bloadphase1';

Beacon get _beacon => Beacon(
  id: _beaconId,
  title: 'Request',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  accessLevel: BeaconAccessLevel.member,
  author: const Profile(id: 'Uauthor', displayName: 'Author'),
);

({
  BeaconViewCubit cubit,
  TrackingBeaconRepository repo,
  FakeUiEffectPort effects,
})
_open(Future<Beacon> Function(int call) read, {String id = _beaconId}) {
  final repo = TrackingBeaconRepository();
  repo.fetchByIdHandler = (_) => read(repo.fetchByIdCalls);
  final effects = FakeUiEffectPort();
  final cubit = BeaconViewCubit(
    id: id,
    myProfile: _viewer,
    beaconViewCase: buildTestBeaconViewCase(beaconRepo: repo),
    effects: effects,
  );
  addTearDown(cubit.close);
  return (cubit: cubit, repo: repo, effects: effects);
}

Future<void> _until(BeaconViewCubit cubit, bool Function() condition) async {
  if (condition()) return;
  await cubit.stream
      .timeout(const Duration(seconds: 3))
      .firstWhere((_) => condition());
}

/// Pins the Request page's own load phases (loading, read, read with its
/// context, unavailable, failed) as the state reports them, before the flags
/// become one value (audit).
void main() {
  test(
    'a Request that cannot be read twice is unavailable, not failed',
    () async {
      final r = _open((_) async => throw const BeaconFetchException());

      await _until(r.cubit, () => r.cubit.state.beaconUnavailable);

      expect(r.repo.fetchByIdCalls, 2);
      expect(r.cubit.state.beaconContentLoaded, isFalse);
      expect(r.cubit.state.beaconContextLoaded, isFalse);
      expect(r.cubit.state.loadError, isNull);
      expect(r.cubit.state.hasError, isFalse);
    },
  );

  test(
    'Try again from unavailable is loading, then shows the Request',
    () async {
      final r = _open((call) async {
        if (call <= 2) throw const BeaconFetchException();
        return _beacon;
      });
      await _until(r.cubit, () => r.cubit.state.beaconUnavailable);

      final retry = r.cubit.retryInitialLoad();
      expect(r.cubit.state.isLoading, isTrue);
      expect(r.cubit.state.beaconUnavailable, isFalse);
      expect(r.cubit.state.beaconContentLoaded, isFalse);
      await retry;

      expect(r.cubit.state.beaconContentLoaded, isTrue);
      expect(r.cubit.state.beaconContextLoaded, isTrue);
      expect(r.cubit.state.beaconUnavailable, isFalse);
      expect(r.cubit.state.loadError, isNull);
    },
  );

  test('a first read that fails for another reason is a load error', () async {
    final r = _open((_) async => throw StateError('database busy'));

    await _until(r.cubit, () => r.cubit.state.hasError);

    expect(r.cubit.state.loadError, isA<StateError>());
    expect(r.cubit.state.beaconUnavailable, isFalse);
    expect(r.cubit.state.beaconContentLoaded, isFalse);
    expect(r.cubit.state.beaconContextLoaded, isFalse);
    expect(r.effects.emitted.whereType<ShowError>(), isEmpty);
  });

  test('Try again after a load error keeps the error until the Request is '
      'read, then clears it', () async {
    final second = Completer<Beacon>();
    final r = _open((call) {
      if (call == 1) return Future.error(StateError('database busy'));
      return second.future;
    });
    await _until(r.cubit, () => r.cubit.state.hasError);

    final retry = r.cubit.retryInitialLoad();
    expect(r.cubit.state.isLoading, isTrue);
    expect(r.cubit.state.hasError, isTrue);
    expect(r.cubit.state.beaconUnavailable, isFalse);

    second.complete(_beacon);
    await retry;

    expect(r.cubit.state.loadError, isNull);
    expect(r.cubit.state.beaconContentLoaded, isTrue);
    expect(r.cubit.state.beaconContextLoaded, isTrue);
  });

  test('a wrong id is a load error from the start', () async {
    final r = _open(
      (_) async => throw const BeaconFetchException(),
      id: 'Xbad',
    );

    expect(r.cubit.state.loadError, 'Wrong id: Xbad');
    expect(r.cubit.state.beaconContentLoaded, isFalse);
    expect(r.cubit.state.beaconUnavailable, isFalse);
    expect(r.effects.emitted.whereType<ShowError>(), hasLength(1));
  });
}
