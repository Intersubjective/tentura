import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

void main() {
  const myProfile = Profile(id: 'Udave', displayName: 'Dave');
  const requestId = 'Bea026c489fab';
  const postId = 'B797e767f5da1';

  final post = Beacon(
    id: postId,
    title: '',
    kind: BeaconKind.post,
    createdAt: DateTime.utc(2026, 10, 24),
    updatedAt: DateTime.utc(2026, 10, 24),
    author: const Profile(id: 'Ualice', displayName: 'Alice'),
  );

  Beacon request({
    BeaconAccessLevel accessLevel = BeaconAccessLevel.observer,
    int accessReasons = 32 | 64,
  }) => Beacon(
    id: requestId,
    title: 'GQ1024 Garden cleanup Saturday',
    createdAt: DateTime.utc(2026, 10, 24, 1),
    updatedAt: DateTime.utc(2026, 10, 24, 1),
    accessLevel: accessLevel,
    accessReasons: accessReasons,
    author: const Profile(id: 'Ualice', displayName: 'Alice'),
  );

  Future<(BeaconViewCubit, List<String>)> load(
    Beacon target, {
    BeaconKind parentKind = BeaconKind.post,
  }) async {
    final fetchedIds = <String>[];
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (id) async {
        fetchedIds.add(id);
        return id == postId ? post.copyWith(kind: parentKind) : target;
      };
    addTearDown(beaconRepo.dispose);
    final cubit = BeaconViewCubit(
      id: requestId,
      myProfile: myProfile,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
      ),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
    return (cubit, fetchedIds);
  }

  test(
    'an observer opens a Request without reading the Post it grew from',
    () async {
      final (cubit, fetchedIds) = await load(request());
      await pumpEventQueue();

      expect(cubit.state.beacon.id, requestId);
      expect(cubit.state.accessParent, isNull);
      expect(cubit.state.accessParentPostExcerpt, isEmpty);
      expect(fetchedIds, [requestId]);
    },
  );

  test('guard: a member of the request does not read the parent', () async {
    final (cubit, fetchedIds) = await load(
      request(accessLevel: BeaconAccessLevel.member, accessReasons: 4 | 64),
    );
    await pumpEventQueue();

    expect(cubit.state.accessParent, isNull);
    expect(fetchedIds, isNot(contains(postId)));
  });

  test('guard: a Request parent is not read for the banner', () async {
    final (cubit, fetchedIds) = await load(
      request(),
      parentKind: BeaconKind.request,
    );
    await pumpEventQueue();

    expect(cubit.state.accessParent, isNull);
    expect(fetchedIds, isNot(contains(postId)));
  });
}
