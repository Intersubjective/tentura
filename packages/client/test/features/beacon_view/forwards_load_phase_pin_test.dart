import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _viewer = Profile(id: 'Uviewer', displayName: 'Viewer');
const _beaconId = 'Bforwardsload1';

/// Forward reads that wait for the test to answer them.
class _GatedForwardRepository extends FakeBeaconViewForwardRepository {
  final pending = <Completer<List<ForwardEdge>>>[];

  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) {
    final read = Completer<List<ForwardEdge>>();
    pending.add(read);
    return read.future;
  }

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: _beacon(BeaconAccessLevel.member),
    forwardedToIds: const <String>{},
    helpOfferedIds: const <String>{},
    withdrawnIds: const <String>{},
    declinedOfferIds: const <String>{},
    rejectedIds: const <String>{},
    watchingIds: const <String>{},
    onwardForwarderIds: const <String>{},
    myForwardedRecipientNotes: const <String, String>{},
    myForwardedRecipientEdgeIds: const <String, String>{},
    myForwardedRecipientReadAts: const <String, DateTime?>{},
    myForwardedRecipientHasOnwardChild: const <String, bool>{},
    myForwardedRecipientRejected: const <String, bool>{},
  );

  @override
  Future<Map<String, List<String>>> fetchReasonsByBeacon({
    required String beaconId,
  }) async => {};
}

Beacon _beacon(BeaconAccessLevel accessLevel) => Beacon(
  id: _beaconId,
  title: 'Request',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  status: BeaconStatus.open,
  canReadContent: true,
  canReadInvolvement: true,
  accessLevel: accessLevel,
  author: const Profile(id: 'Uauthor', displayName: 'Author'),
);

ForwardEdge get _edge => ForwardEdge(
  id: 'e1',
  beaconId: _beaconId,
  createdAt: DateTime.utc(2026),
  sender: _viewer,
  recipient: const Profile(id: 'Uother', displayName: 'Other'),
);

Future<({BeaconViewCubit cubit, _GatedForwardRepository forwards})> _open({
  BeaconAccessLevel accessLevel = BeaconAccessLevel.member,
}) async {
  final forwards = _GatedForwardRepository();
  final cubit = BeaconViewCubit(
    id: _beaconId,
    myProfile: _viewer,
    beaconViewCase: buildTestBeaconViewCase(
      beaconRepo: TrackingBeaconRepository()
        ..fetchByIdHandler = (_) async => _beacon(accessLevel),
      forward: forwards,
    ),
    effects: FakeUiEffectPort(),
  );
  addTearDown(cubit.close);
  await _until(cubit, () => cubit.state.firstLoadDone);
  return (cubit: cubit, forwards: forwards);
}

Future<void> _until(BeaconViewCubit cubit, bool Function() condition) async {
  if (condition()) return;
  await cubit.stream
      .timeout(const Duration(seconds: 2))
      .firstWhere((_) => condition());
}

Future<void> _settle() => Future<void>.delayed(Duration.zero);

/// Pins the People › Forwards lazy-load phases (idle, loading, loaded) as the
/// state reports them, before the two flags become one value (audit).
void main() {
  test('first load leaves forwards unread and idle', () async {
    final r = await _open();

    expect(r.forwards.pending, isEmpty);
    expect(r.cubit.state.forwardsLoaded, isFalse);
    expect(r.cubit.state.forwardsLoading, isFalse);
  });

  test('loadForwards is loading until the read answers, then loaded', () async {
    final r = await _open();

    final load = r.cubit.loadForwards();
    await _settle();
    expect(r.cubit.state.forwardsLoading, isTrue);
    expect(r.cubit.state.forwardsLoaded, isFalse);

    r.forwards.pending.single.complete([_edge]);
    await load;
    expect(r.cubit.state.forwardsLoading, isFalse);
    expect(r.cubit.state.forwardsLoaded, isTrue);
    expect(r.cubit.state.viewerForwardEdges, isNotEmpty);
  });

  test('a second loadForwards while one is in flight reads nothing more',
      () async {
    final r = await _open();

    final first = r.cubit.loadForwards();
    await _settle();
    await r.cubit.loadForwards();
    expect(r.forwards.pending, hasLength(1));

    r.forwards.pending.single.complete(const []);
    await first;
    await r.cubit.loadForwards();
    expect(r.forwards.pending, hasLength(1));
    expect(r.cubit.state.forwardsLoaded, isTrue);
  });

  test('a failed read goes back to idle and the next load reads again',
      () async {
    final r = await _open();

    final failed = r.cubit.loadForwards();
    await _settle();
    r.forwards.pending.single.completeError(StateError('offline'));
    await failed;
    expect(r.cubit.state.forwardsLoading, isFalse);
    expect(r.cubit.state.forwardsLoaded, isFalse);

    final retry = r.cubit.loadForwards();
    await _settle();
    expect(r.forwards.pending, hasLength(2));
    expect(r.cubit.state.forwardsLoading, isTrue);
    r.forwards.pending.last.complete(const []);
    await retry;
    expect(r.cubit.state.forwardsLoaded, isTrue);
  });

  test('an observer never starts the forwards read', () async {
    final r = await _open(accessLevel: BeaconAccessLevel.observer);

    await r.cubit.loadForwards();
    expect(r.forwards.pending, isEmpty);
    expect(r.cubit.state.forwardsLoading, isFalse);
    expect(r.cubit.state.forwardsLoaded, isFalse);
  });
}
