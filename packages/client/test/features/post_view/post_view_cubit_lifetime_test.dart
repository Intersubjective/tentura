// The Post cubit's author lifetime writes: `shorten` asks for an end
// [duration] after the cubit's clock, `closeNow` closes the Post.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/post_view/data/repository/post_membership_repository.dart';
import 'package:tentura/features/post_view/domain/use_case/post_view_case.dart';
import 'package:tentura/features/post_view/ui/bloc/post_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';

const _postId = 'Bpostlife002';
const _author = Profile(id: 'Uauthor', displayName: 'Олег');

final _start = DateTime.utc(2026, 10, 3, 12);

class _PostRepository implements BeaconRepository {
  _PostRepository(this.beacon);

  final Beacon beacon;

  @override
  Stream<RepositoryEvent<Beacon>> get changes => const Stream.empty();

  @override
  Future<Beacon> fetchBeaconById(String id) async => beacon;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ForwardRepository implements ForwardRepository {
  @override
  Future<List<ForwardEdge>> fetchEdges({required String beaconId}) async =>
      const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PostsRepository implements PostsRepositoryPort {
  @override
  Future<List<PostSummary>> myPosts() async => const [];

  @override
  Future<PostSummary?> postSummary(String id) async => null;
}

class _MembershipRepository implements PostMembershipRepository {
  final shortenCalls = <({String beaconId, DateTime expiresAt})>[];
  final closeCalls = <String>[];

  @override
  Future<void> postShorten(
    String beaconId, {
    required DateTime expiresAt,
  }) async {
    shortenCalls.add((beaconId: beaconId, expiresAt: expiresAt));
  }

  @override
  Future<void> postClose(String beaconId) async {
    closeCalls.add(beaconId);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _MembershipRepository membership;
  late PostViewCubit cubit;

  setUp(() async {
    membership = _MembershipRepository();
    cubit = PostViewCubit(
      id: _postId,
      myProfile: _author,
      beaconRepository: _PostRepository(
        Beacon(
          id: _postId,
          kind: BeaconKind.post,
          createdAt: _start.subtract(const Duration(days: 1)),
          updatedAt: _start.subtract(const Duration(days: 1)),
          author: _author,
          expiresAt: _start.add(const Duration(hours: 30)),
        ),
      ),
      postViewCase: PostViewCase(_PostsRepository(), _ForwardRepository()),
      membershipRepository: membership,
      effects: FakeUiEffectPort(),
      clock: () => _start,
    );
    addTearDown(cubit.close);
    await cubit.fetch();
  });

  test('shorten asks for an end the given duration after the clock', () async {
    await cubit.shorten(const Duration(hours: 6));

    expect(membership.shortenCalls, hasLength(1));
    expect(membership.shortenCalls.single.beaconId, _postId);
    expect(
      membership.shortenCalls.single.expiresAt.toUtc(),
      _start.add(const Duration(hours: 6)),
    );
    expect(membership.closeCalls, isEmpty);
  });

  test('closeNow calls postClose for the Post', () async {
    await cubit.closeNow();

    expect(membership.closeCalls, [_postId]);
    expect(membership.shortenCalls, isEmpty);
  });
}
