import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_access.dart';
import 'package:tentura_root/domain/entity/beacon_parent_reference.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../domain/use_case/fake_beacon_hierarchy_ports.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';
import 'beacon_view_initial_load_test.dart';

/// #724: a member of a Post opening a Request budded from it was told they
/// "take part in a related request". The banner can only name the Post once
/// the Request's parent has been read; the screen reads it for a viewer who
/// sees the Request through it, and for no one else.
///
/// Realistic data (QA on dev, 7.52.1): a budded Request carries the Post as
/// its hierarchy (nesting) parent — `beaconParentReference` — and has no
/// lineage parent; a declined post member reads it with discovered |
/// contextChild (32 | 64).
///
/// The parent is read through `BeaconViewCase` (review r1 #7: no second use
/// case pulled from GetIt by the cubit).
void main() {
  const myProfile = Profile(id: 'Udave', displayName: 'Dave');
  const requestId = 'Bea026c489fab';
  const postId = 'B797e767f5da1';

  final post = Beacon(
    id: postId,
    title: 'GQ1024: planning a weekend',
    kind: BeaconKind.post,
    createdAt: DateTime.utc(2026, 10, 24),
    updatedAt: DateTime.utc(2026, 10, 24),
    author: const Profile(id: 'Ualice', displayName: 'Alice'),
  );

  const postReference = BeaconParentReference(
    state: BeaconParentReferenceState.available,
    beaconId: postId,
    title: 'GQ1024: planning a weekend',
    isPost: true,
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
    BeaconParentReference reference = postReference,
  }) async {
    final fetchedIds = <String>[];
    final beaconRepo = TrackingBeaconRepository()
      ..fetchByIdHandler = (id) async {
        fetchedIds.add(id);
        return id == postId ? post : target;
      };
    addTearDown(beaconRepo.dispose);
    final cubit = BeaconViewCubit(
      id: requestId,
      myProfile: myProfile,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        hierarchyRepository: FakeBeaconHierarchyRepositoryPort(
          parentReference: reference,
        ),
      ),
      effects: FakeUiEffectPort(),
    );
    addTearDown(cubit.close);
    await pumpUntil(cubit.stream, () => cubit.state.beaconContextLoaded);
    return (cubit, fetchedIds);
  }

  test('a post member sees the request with its parent post read', () async {
    final (cubit, _) = await load(request());
    await pumpUntilCondition(() => cubit.state.accessParent != null);

    expect(cubit.state.accessParent?.id, postId);
    expect(cubit.state.accessParent?.kind, BeaconKind.post);
    expect(cubit.state.accessParent?.title, 'GQ1024: planning a weekend');
  });

  test('guard: a member of the request does not read the parent', () async {
    final (cubit, fetchedIds) = await load(
      request(accessLevel: BeaconAccessLevel.member, accessReasons: 4 | 64),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(cubit.state.accessParent, isNull);
    expect(fetchedIds, isNot(contains(postId)));
  });

  test('guard: a Request parent is not read for the banner', () async {
    final (cubit, fetchedIds) = await load(
      request(),
      reference: const BeaconParentReference(
        state: BeaconParentReferenceState.available,
        beaconId: postId,
        title: 'Parent request',
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 100));

    expect(cubit.state.accessParent, isNull);
    expect(fetchedIds, isNot(contains(postId)));
  });
}
