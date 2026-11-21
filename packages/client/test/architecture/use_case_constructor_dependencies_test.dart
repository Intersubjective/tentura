import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/repository/presence_repository.dart';
import 'package:tentura/data/service/bookkeeping_refresh_signal.dart';
import 'package:tentura/data/service/invalidation_service.dart';
import 'package:tentura/domain/capability/forward_band_row.dart';
import 'package:tentura/domain/contacts/contact_name_store.dart';
import 'package:tentura/domain/entity/availability.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/author_invite_port.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/domain/port/post_bud_port.dart';
import 'package:tentura/domain/use_case/author_invite_case.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/post_bud_repository.dart';
import 'package:tentura/features/beacon_plan/domain/entity/beacon_plan.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_threads/domain/use_case/beacon_threads_case.dart';
import 'package:tentura/features/closure/data/repository/closure_repository.dart';
import 'package:tentura/features/closure/domain/use_case/closure_case.dart';
import 'package:tentura/features/complaint/data/repository/complaint_repository.dart';
import 'package:tentura/features/complaint/domain/use_case/complaint_case.dart';
import 'package:tentura/features/contacts/domain/use_case/contacts_case.dart';
import 'package:tentura/features/credentials/domain/use_case/credentials_case.dart';
import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/use_case/forward_case.dart';
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
import 'package:tentura/features/profile/data/repository/profile_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';
import 'package:tentura/features/profile_view/data/repository/profile_shared_beacons_repository.dart';
import 'package:tentura/features/profile_view/domain/use_case/profile_shared_beacons_case.dart';

import '../features/auth/auth_test_helpers.dart'
    show EmptyAuthLocal, EmptyAuthRemote, buildTestAuthCase;
import '../features/beacon_plan/beacon_plan_test_support.dart'
    show FakeBeaconPlanRepository, planJson;
import '../features/beacon_threads/room_cubit_fakes.dart'
    show
        FakeBeaconFactCardRepository,
        FakeBeaconRoomHintsRepository,
        FakeBeaconThreadsRepository,
        FakePollingRepository;
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
import '../features/realtime/read_cursor_server_frames.dart';
import '../support/fake_block_case.dart';
import '../support/remote_wire_harness.dart';
import '../support/test_realtime_sync.dart';
import '../support/users_fetch_by_ids_wire.dart';

class _FakeAuthorInvitePort extends Fake implements AuthorInvitePort {}

class _FakeCapabilities extends Fake implements CapabilityRepositoryPort {}

class _FakeInvitationRepository extends Fake implements InvitationRepository {}

class _FakeLikeRepository extends Fake implements LikeRemoteRepository {}

class _FakeFriendsRepository extends Fake implements FriendsRemoteRepository {}

class _FakePresenceRepository extends Fake implements PresenceRepository {}

class _FakeInboxRepository extends Fake implements InboxRepository {}

class _FakePostsRepository extends Fake implements PostsRepositoryPort {}

class _FakeForwardRepository extends Fake implements ForwardRepository {}

class _ForwardChangesRepository extends _FakeForwardRepository {
  _ForwardChangesRepository(this.forwardChanges);

  @override
  final Stream<String> forwardChanges;
}

class _ForwardAvailabilityRepository extends _FakeForwardRepository {
  _ForwardAvailabilityRepository(this.candidates);

  final List<Profile> candidates;

  @override
  Future<Iterable<Profile>> fetchForwardCandidates({
    String context = '',
  }) async => candidates;

  @override
  Future<BeaconInvolvementData> fetchBeaconInvolvement({
    required String beaconId,
  }) async => (
    beacon: Beacon.empty.copyWith(id: beaconId),
    forwardedToIds: <String>{},
    helpOfferedIds: <String>{},
    withdrawnIds: <String>{},
    declinedOfferIds: <String>{},
    rejectedIds: <String>{},
    watchingIds: <String>{},
    onwardForwarderIds: <String>{},
    myForwardedRecipientNotes: <String, String>{},
    myForwardedRecipientEdgeIds: <String, String>{},
    myForwardedRecipientReadAts: <String, DateTime?>{},
    myForwardedRecipientHasOnwardChild: <String, bool>{},
    myForwardedRecipientRejected: <String, bool>{},
  );
}

class _ForwardBandRepository extends _FakeCapabilities {
  _ForwardBandRepository(this.rows);

  final List<ForwardBandRow> rows;

  @override
  Future<List<ForwardBandRow>> fetchForwardContext({
    required String beaconId,
    String? context,
  }) async => rows;

  @override
  Future<Map<String, List<String>>> fetchTopCapabilitiesBatch({
    required List<String> subjectIds,
    int limit = 2,
    List<String> prioritizeSlugs = const [],
  }) async => {};
}

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

    test(
      'BeaconThreadsCase observes server read cursors with only its feature dependencies',
      () async {
        const beaconId = 'Bbeacon0000001';
        const readerId = 'Uuseraaaaaaaa01';
        final watermark = RoomReadWatermarkStore.testing();
        addTearDown(watermark.dispose);
        final room = FakeBeaconThreadsRepository(userId: readerId);
        addTearDown(room.dispose);
        final frames = StreamController<Map<String, dynamic>>.broadcast();
        addTearDown(frames.close);
        final invalidations = InvalidationService.forTesting(frames.stream);
        addTearDown(invalidations.dispose);

        final threads = _expectFeatureDependenciesOnly<BeaconThreadsCase>(
          BeaconThreadsCase.new,
          [
            room,
            FakeBeaconFactCardRepository(),
            FakePollingRepository(),
            FakeBeaconRoomHintsRepository(),
            watermark,
            RealtimeSyncCase(invalidations),
          ],
        );

        final notice = threads.readWatermarkChanges.first;
        final seenAt = DateTime.utc(2026, 8, 14, 10);
        frames.add(
          roomSeenReadCursorFrame(
            readerId: readerId,
            beaconId: beaconId,
            at: seenAt,
            event: 'update',
          ),
        );
        expect(await notice.timeout(const Duration(seconds: 3)), beaconId);
        expect(watermark.syncedAt(beaconId), seenAt);
      },
    );

    test('CredentialsCase only needs credentials and local auth', () {
      _expectFeatureDependenciesOnly<CredentialsCase>(CredentialsCase.new, [
        FakeCredentialsRepository(),
        TrackingAuthLocal(),
      ]);
    });

    test(
      'ForwardCase relays changed beacon ids with only its feature dependencies',
      () async {
        const beaconId = 'Bbeacon0000001';
        final changes = StreamController<String>.broadcast();
        addTearDown(changes.close);
        final forward = _expectFeatureDependenciesOnly<ForwardCase>(
          ForwardCase.new,
          _forwardDependencies(_ForwardChangesRepository(changes.stream)),
        );

        final changedBeacon = forward.forwardChanges.first;
        changes.add(beaconId);
        expect(
          await changedBeacon.timeout(const Duration(seconds: 3)),
          beaconId,
        );
      },
    );

    test(
      'ForwardCase uses the current UTC date for recipient availability',
      () async {
        const resumed = 'Uresumed00001';
        const paused = 'Upaused000001';
        final now = DateTime.now().toUtc();
        final today = DateTime.utc(now.year, now.month, now.day);
        final tomorrow = today.add(const Duration(days: 1));
        final repository = _ForwardAvailabilityRepository([
          Profile(
            id: resumed,
            availability: Availability(resumeOn: today),
          ),
          Profile(
            id: paused,
            availability: Availability(resumeOn: tomorrow),
          ),
        ]);
        GetIt.I.registerSingleton<CapabilityRepositoryPort>(
          _ForwardBandRepository(const [
            ForwardBandRow(userId: resumed),
            ForwardBandRow(userId: paused),
          ]),
        );
        addTearDown(() => GetIt.I.unregister<CapabilityRepositoryPort>());

        final forward = _expectFeatureDependenciesOnly<ForwardCase>(
          ForwardCase.new,
          _forwardDependencies(repository),
        );
        final load = await forward.loadForwardCandidates(
          beaconId: 'Bbeacon0000001',
        );

        final bandIds = load.band.map((row) => row.userId);
        // Either result is possible if loading spanned UTC midnight.
        expect(
          bandIds,
          DateTime.now().toUtc().isBefore(tomorrow)
              ? orderedEquals([resumed])
              : anyOf(
                  orderedEquals([resumed]),
                  orderedEquals([resumed, paused]),
                ),
        );
      },
    );

    test(
      'ForwardCase loads Post invite candidates through the registered port',
      () async {
        const memberId = 'Umember00001';
        await withCappedUsersWire(
          <WireSent>[],
          (remote) async {
            GetIt.I.registerSingleton<PostBudPort>(PostBudRepository(remote));
            addTearDown(() => GetIt.I.unregister<PostBudPort>());
            final forward = _expectFeatureDependenciesOnly<ForwardCase>(
              ForwardCase.new,
              _forwardDependencies(
                _FakeForwardRepository(),
                profiles: ProfileRepository(remote),
              ),
            );

            final load = await forward.loadPostBudInviteCandidates(
              'Bpost00000001',
            );

            expect(load.candidates.map((candidate) => candidate.profile.id), [
              memberId,
            ]);
            expect(
              load.candidates.single.profile.displayName,
              'Name of $memberId',
            );
            expect(load.autoSelectIds, {memberId});
          },
          responses: const {
            'PostBudInviteCandidates': {
              '__typename': 'query_root',
              'postBudInviteCandidates': [
                {
                  '__typename': 'PostBudInviteCandidate',
                  'userId': memberId,
                  'warm': true,
                  'outcome': 'invited',
                  'pretick': true,
                  'viaUserId': null,
                  'hasWritten': true,
                },
              ],
            },
          },
        );
      },
    );

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

List<Object> _forwardDependencies(
  ForwardRepository repository, {
  ProfileRepositoryPort? profiles,
}) {
  final authLocal = EmptyAuthLocal();
  final realtime = buildTestRealtimeSync();
  addTearDown(realtime.port.dispose);
  final contactStore = ContactNameStore();
  addTearDown(contactStore.dispose);
  final contacts = ContactsCase(
    FakeContactsRepository(),
    buildTestAuthCase(authLocal, EmptyAuthRemote()),
    contactStore,
    realtime.case_,
    env: const Env(),
    logger: Logger('ContactsCaseTest'),
  );
  addTearDown(contacts.dispose);
  return [
    repository,
    authLocal,
    FakeBeaconFactCardRepository(),
    profiles ?? FakeComplaintProfiles(),
    contacts,
    FakeBlockCase(),
  ];
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
