import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/port/author_invite_port.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/complaint/data/repository/complaint_repository.dart';
import 'package:tentura/features/complaint/domain/use_case/complaint_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward_candidate_context/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura/features/forward_candidate_context/domain/use_case/load_forward_candidate_context_case.dart';
import 'package:tentura/features/friends/data/repository/friends_remote_repository.dart';
import 'package:tentura/features/friends/domain/use_case/friends_case.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/inbox_case.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/features/invitation/data/repository/invitation_repository.dart';
import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';
import 'package:tentura/features/profile_view/data/repository/profile_shared_beacons_repository.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_shared_beacons_case.dart';

import '../features/auth/auth_test_helpers.dart'
    show EmptyAuthLocal, EmptyAuthRemote, buildTestAuthCase;
import '../features/beacon_plan/beacon_plan_test_support.dart'
    show FakeBeaconPlanRepository, planJson;
import '../features/beacon_view/beacon_view_case_test_support.dart'
    show FakeBeaconDisplayRepository;
import '../features/complaint/recording_complaint_case.dart'
    show FakeComplaintBeacons, FakeComplaintProfiles;
import '../features/contacts/contacts_case_test.dart'
    show FakeContactsRepository;
import '../features/credentials/credentials_case_test.dart'
    show FakeCredentialsRepository, TrackingAuthLocal;
import '../features/inbox/inbox_case_test.dart' show buildTestBeaconThreadsCase;
import '../features/my_work/my_work_test_support.dart' as my_work;
import '../support/fake_block_case.dart';
import '../support/test_realtime_sync.dart';

class _FakeAuthorInvitePort extends Fake implements AuthorInvitePort {}

class _FakeCapabilities extends Fake implements CapabilityRepositoryPort {}

class _FakeInvitationRepository extends Fake implements InvitationRepository {}

class _FakeLikeRepository extends Fake implements LikeRemoteRepository {}

class _FakeFriendsRepository extends Fake implements FriendsRemoteRepository {}

class _FakePresenceRepository extends Fake implements PresenceRepository {}

class _FakeInboxRepository extends Fake implements InboxRepository {}

class _FakePostsRepository extends Fake implements PostsRepositoryPort {}

class _FakeForwardRepository extends Fake implements ForwardRepository {}

class _FakeClosureRepository extends Fake implements ClosureRepository {}

class _FakeComplaintRepository extends Fake implements ComplaintRepository {}

class _FakeForwardCandidateContextRepository extends Fake
    implements ForwardCandidateContextRepositoryPort {}

class _FakeSharedBeaconsRepository extends Fake
    implements ProfileSharedBeaconsRepository {}

void main() {
  group('Use cases construct without environment or logger', () {
    test('AuthorInviteCase only needs its author invitation port', () {
      _expectFeatureDependenciesOnly<AuthorInviteCase>(AuthorInviteCase.new, [
        _FakeAuthorInvitePort(),
      ]);
    });

    test('CredentialsCase only needs credentials and local auth', () {
      _expectFeatureDependenciesOnly<CredentialsCase>(CredentialsCase.new, [
        FakeCredentialsRepository(),
        TrackingAuthLocal(),
      ]);
    });

    test('FriendsCase only needs its feature dependencies', () {
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final auth = buildTestAuthCase(EmptyAuthLocal(), EmptyAuthRemote());
      final contactStore = ContactNameStore();
      addTearDown(contactStore.dispose);
      final contacts = ContactsCase(
        FakeContactsRepository(),
        auth,
        contactStore,
        realtime.case_,
        env: const Env(),
        logger: Logger('ContactsCaseTest'),
      );
      addTearDown(contacts.dispose);

      _expectFeatureDependenciesOnly<FriendsCase>(FriendsCase.new, [
        _FakeCapabilities(),
        _FakeInvitationRepository(),
        _FakeLikeRepository(),
        _FakeFriendsRepository(),
        _FakePresenceRepository(),
        contacts,
        auth,
        realtime.case_,
        FakeBlockCase(),
      ]);
    });

    test('InboxCase only needs its feature dependencies', () {
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final bookkeepingRefresh = BookkeepingRefreshSignal();
      addTearDown(bookkeepingRefresh.dispose);

      _expectFeatureDependenciesOnly<InboxCase>(InboxCase.new, [
        _FakeInboxRepository(),
        buildTestBeaconThreadsCase(),
        _FakeForwardRepository(),
        realtime.case_,
        bookkeepingRefresh,
        FakeBlockCase(),
      ]);
    });

    test('PostsCase only needs its feature dependencies', () {
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final dependencies = [_FakePostsRepository(), realtime.case_];
      final beaconRepository = my_work.FakeBeaconRepository();

      _expectFeatureDependenciesOnly<PostsCase>(PostsCase.new, dependencies);
      final posts =
          Function.apply(PostsCase.new, dependencies, {
                #beaconRepository: beaconRepository,
              })
              as PostsCase;
      expect(posts.beaconRepository, same(beaconRepository));
    });

    test('PostsCase factory accepts only its feature dependencies', () {
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final beaconRepository = my_work.FakeBeaconRepository();

      final posts = _expectFeatureDependenciesOnly<PostsCase>(
        PostsCase.withBeaconRepository,
        [_FakePostsRepository(), realtime.case_],
        namedDependencies: {#beaconRepository: beaconRepository},
      );
      expect(posts.beaconRepository, same(beaconRepository));
    });

    test('MyWorkCase only needs its feature dependencies', () {
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);
      final bookkeepingRefresh = BookkeepingRefreshSignal();
      addTearDown(bookkeepingRefresh.dispose);
      final roomHints = my_work.FakeRoomHints();

      final dependencies = <Object>[
        my_work.FakeMyWorkRepository(),
        my_work.FakeArchiveRepository(),
        my_work.FakeForwardRepository(),
        my_work.FakeBeaconRepository(),
        my_work.buildTestBeaconThreadsCase(roomHints),
        roomHints,
        FakeBeaconDisplayRepository(),
        my_work.FakeMyWorkClosureRepository(),
        realtime.case_,
        bookkeepingRefresh,
        my_work.buildStubAttentionCase(realtimeSyncCase: realtime.case_),
        FakeBeaconPlanRepository(BeaconPlan.decode(planJson())),
      ];

      _expectFeatureDependenciesOnly<MyWorkCase>(MyWorkCase.new, dependencies);
      expect(
        () => Function.apply(MyWorkCase.new, [...dependencies, null]),
        throwsNoSuchMethodError,
        reason: 'MyWorkCase must reject a thirteenth positional argument',
      );
    });
  });

  test(
    'ComplaintCase can be constructed with only its feature dependencies',
    () {
      // Keep the fixture compilable while the old signature is still present.
      final credentials =
          Function.apply(CredentialsCase.new, [
                FakeCredentialsRepository(),
                TrackingAuthLocal(),
              ])
              as CredentialsCase;

      _expectFeatureDependenciesOnly<ComplaintCase>(ComplaintCase.new, [
        _FakeComplaintRepository(),
        credentials,
        FakeComplaintBeacons(),
        FakeComplaintProfiles(),
      ]);
    },
  );

  test(
    'ProfileSharedBeaconsCase only needs its repository and realtime sync',
    () {
      final realtime = buildTestRealtimeSync();
      addTearDown(realtime.port.dispose);

      _expectFeatureDependenciesOnly<ProfileSharedBeaconsCase>(
        ProfileSharedBeaconsCase.new,
        [_FakeSharedBeaconsRepository(), realtime.case_],
      );
    },
  );

  test('ClosureCase only needs its repository', () {
    _expectFeatureDependenciesOnly<ClosureCase>(ClosureCase.new, [
      _FakeClosureRepository(),
    ]);
  });

  test('LoadForwardCandidateContextCase only needs its repository port', () {
    _expectFeatureDependenciesOnly<LoadForwardCandidateContextCase>(
      LoadForwardCandidateContextCase.new,
      [_FakeForwardCandidateContextRepository()],
    );
  });
}

T _expectFeatureDependenciesOnly<T>(
  Function constructor,
  List<Object> dependencies, {
  Map<Symbol, Object> namedDependencies = const {},
}) {
  // Invoke the real constructor with the desired arguments while keeping the
  // test compilable with the old signature.
  late final Object instance;
  expect(
    () => instance =
        Function.apply(constructor, dependencies, namedDependencies) as Object,
    returnsNormally,
    reason: '$T must be constructible without env or logger',
  );
  expect(instance, isA<T>());
  expect(instance is UseCaseBase, isFalse);

  // Supplying either argument must also fail if it was left behind as optional.
  expect(
    () => Function.apply(constructor, dependencies, {
      ...namedDependencies,
      #env: const Env(),
    }),
    throwsNoSuchMethodError,
    reason: '$T must not accept env',
  );
  expect(
    () => Function.apply(constructor, dependencies, {
      ...namedDependencies,
      #logger: Logger('test'),
    }),
    throwsNoSuchMethodError,
    reason: '$T must not accept logger',
  );
  return instance as T;
}
