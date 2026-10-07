import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';

import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/domain/entity/commitment_stake_state.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/features/beacon_view/domain/use_case/beacon_view_case.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';
import 'package:tentura/features/constellation/domain/port/constellation_repository_port.dart';
import 'package:tentura/features/constellation/domain/use_case/constellation_field_case.dart';
import 'package:tentura/features/constellation/ui/bloc/constellation_cubit.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_cubit.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../beacon_view/beacon_view_case_test_support.dart';
import '../inbox/inbox_case_test.dart'
    show FakeInboxRepository, buildTestBeaconThreadsCase, buildTestInboxCase;
import '../my_work/my_work_test_support.dart'
    show FakeMyWorkRepository, buildStubAttentionCase, buildTestMyWorkCase;

const _id = 'Bconverted01';
const _helper = Profile(id: 'Uhelperlive01', displayName: 'Helper');
const _author = Profile(id: 'Uauthorlive01', displayName: 'Author');

Beacon _post() => Beacon.empty.copyWith(
  id: _id,
  kind: BeaconKind.post,
  author: _author,
  canReadContent: true,
);

Beacon _request() => _post().copyWith(
  kind: BeaconKind.request,
  title: 'Help move a piano',
  description: 'Third floor, no lift, Saturday.',
);

const _hint = RealtimeEntityChange(
  kind: RealtimeEntityKind.beacon,
  aggregateId: _id,
  operation: RealtimeOperation.update,
  source: RealtimeChangeSource.serverInvalidation,
);

class _BeaconSnapshots extends BeaconRepository {
  _BeaconSnapshots(RemoteApiService remote, TestRealtimeSyncPort port)
    : super(remote, port);

  Beacon snapshot = _post();
  int fetchCount = 0;

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    expect(id, _id);
    fetchCount++;
    return snapshot;
  }

  @override
  Future<List<Profile>> fetchAdmittedHelpers(String id) async => [_helper];

  @override
  Future<Set<String>> fetchTeamAcquaintanceIds(String id) async => const {};
}

class _FieldSnapshots implements ConstellationRepositoryPort {
  bool converted = false;
  int fetchCount = 0;

  @override
  Future<ConstellationField> fetch({
    ConstellationFieldMembershipFilters membershipFilters =
        ConstellationFieldMembershipFilters.defaults,
    ConstellationProjection projection = ConstellationProjection.full,
  }) async {
    fetchCount++;
    return ConstellationField(
      loadedAt: DateTime.utc(2026, 10, 1),
      context: '',
      posts: converted
          ? const []
          : [
              ConstellationPost(
                id: _id,
                authorId: _author.id,
                rootExcerpt: 'Anyone around on Saturday?',
                lastActivityAt: DateTime.utc(2026, 10, 1),
                isPinned: false,
              ),
            ],
      requests: converted
          ? [
              ConstellationRequest(
                id: _id,
                authorId: _author.id,
                title: _request().title,
                status: 0,
                viewerIsRoomParticipant: true,
              ),
            ]
          : const [],
    );
  }
}

void main() {
  group('Converted Requests converge across client projections', () {
    test(
      'a beacon hint changes the Activity row from Post to Request',
      () async {
        final sync = buildTestRealtimeSync();
        addTearDown(sync.port.dispose);
        final repository = FakeInboxRepository()
          ..fetchResult = [
            InboxItem(
              beaconId: _id,
              latestForwardAt: DateTime.utc(2026, 10, 1),
              beacon: _post(),
            ),
          ];
        addTearDown(repository.dispose);
        final cubit = InboxCubit(
          userId: _helper.id,
          inboxCase: buildTestInboxCase(
            repository,
            buildTestBeaconThreadsCase(),
            realtimeSyncCase: sync.case_,
          ),
          effects: FakeUiEffectPort(),
        );
        addTearDown(cubit.close);
        await cubit.stream.firstWhere((state) => state.projectionLoaded);
        expect(cubit.state.items.single.beacon!.kind, BeaconKind.post);
        final fetchesBefore = repository.fetchCallCount;

        repository.fetchResult = [
          repository.fetchResult.single.copyWith(beacon: _request()),
        ];
        sync.port.emitChange(_hint);
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(repository.fetchCallCount, greaterThan(fetchesBefore));
        expect(cubit.state.items.single.beacon!.kind, BeaconKind.request);
        expect(cubit.state.items.single.beacon!.title, _request().title);
      },
    );

    test(
      'My Work automatically displays a converted Request for its new helper',
      () async {
        final sync = buildTestRealtimeSync();
        addTearDown(sync.port.dispose);
        final repository = FakeMyWorkRepository();
        final attention = buildStubAttentionCase(realtimeSyncCase: sync.case_);
        addTearDown(attention.dispose);
        final case_ = buildTestMyWorkCase(
          repo: repository,
          attentionCase: attention,
          realtimeSyncCase: sync.case_,
        );
        final cubit = MyWorkCubit(userId: _helper.id, myWorkCase: case_);
        addTearDown(cubit.close);
        await cubit.stream.firstWhere(
          (state) => state.nonArchivedProjectionLoaded,
        );
        expect(cubit.state.nonArchivedProjectionLoaded, isTrue);
        expect(cubit.state.nonArchivedCards, isEmpty);
        final fetchesBefore = repository.fetchInitCallCount;

        repository.initResult = (
          authoredNonArchived: const <Beacon>[],
          helpOfferedNonArchived: [
            (
              beacon: _request(),
              offerHelpMessage: '',
              helpType: null,
              authorResponseType: null,
              stakeState: CommitmentStakeState.none,
              forwarderSenders: const <Profile>[],
              helpOfferRowUpdatedAt: DateTime.utc(2026, 10, 1),
              authorCoordinationUpdatedAt: null,
            ),
          ],
          obligationBeacons: const [],
          archivedCountHint: 0,
        );
        final refreshed = cubit.stream.firstWhere(
          (state) => state.nonArchivedCards.isNotEmpty,
        );
        sync.port.emitChange(_hint);
        final after = await refreshed.timeout(const Duration(seconds: 2));
        expect(repository.fetchInitCallCount, greaterThan(fetchesBefore));
        expect(after.nonArchivedCards.single.beaconId, _id);
        expect(after.nonArchivedCards.single.beacon.kind, BeaconKind.request);
        expect(after.nonArchivedCards.single.beacon.title, _request().title);
      },
    );

    test(
      'a beacon hint replaces the Post with a Request in the field',
      () async {
        final sync = buildTestRealtimeSync();
        addTearDown(sync.port.dispose);
        final repository = _FieldSnapshots();
        final cubit = ConstellationCubit(
          case_: ConstellationFieldCase(
            repository,
            env: const Env.fromEnvironment(),
            logger: Logger('PostConversionFieldTest'),
            realtimeSyncCase: sync.case_,
          ),
          viewer: _helper,
        );
        addTearDown(cubit.close);
        await cubit.stream.firstWhere((state) => state.field != null);
        expect(cubit.state.field!.posts.single.id, _id);
        expect(cubit.state.field!.requests, isEmpty);
        final fetchesBefore = repository.fetchCount;

        repository.converted = true;
        sync.port.emitChange(_hint);
        await Future<void>.delayed(const Duration(seconds: 3));

        expect(repository.fetchCount, greaterThan(fetchesBefore));
        expect(cubit.state.field!.posts, isEmpty);
        expect(cubit.state.field!.requests.single.id, _id);
        expect(cubit.state.field!.requests.single.title, _request().title);
      },
    );

    test('a beacon hint refetches an open beacon view as a Request', () async {
      final sync = buildTestRealtimeSync();
      addTearDown(sync.port.dispose);
      final remote = RemoteApiService(
        const Env.fromEnvironment(),
        const WebSocketClientRealtimeSocketFactory(),
      );
      addTearDown(remote.close);
      final repository = _BeaconSnapshots(remote, sync.port);
      addTearDown(repository.dispose);
      final forwards = FakeBeaconViewForwardRepository();
      addTearDown(forwards.dispose);
      final room = FakeBeaconViewRoomRepository();
      addTearDown(room.dispose);
      final effects = FakeUiEffectPort();
      final cubit = BeaconViewCubit(
        id: _id,
        myProfile: _helper,
        beaconViewCase: BeaconViewCase(
          repository,
          forwards,
          FakeBeaconViewClosureRepository(),
          FakeBeaconViewArchiveRepository(),
          FakeBeaconViewCoordinationRepository(),
          FakeBeaconDisplayRepository(),
          FakeBeaconViewInboxRepository(),
          FakeBeaconViewFactCardRepository(),
          buildTestBeaconThreadsCaseForView(
            RoomReadWatermarkStore.testing(),
            room: room,
          ),
          FakeBeaconViewActivityEventRepository(),
          sync.case_,
          env: const Env(),
          logger: Logger('PostConversionBeaconViewTest'),
        ),
        effects: effects,
      );
      addTearDown(cubit.close);
      await cubit.stream
          .firstWhere((state) => state.beaconContextLoaded)
          .timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail(
              'Initial beacon context failed: '
              '${effects.emitted.whereType<ShowError>().map((e) => e.error)}',
            ),
          );
      expect(cubit.state.beacon.kind, BeaconKind.post);
      final fetchesBefore = repository.fetchCount;

      repository.snapshot = _request();
      sync.port.emitChange(_hint);
      await Future<void>.delayed(const Duration(milliseconds: 400));

      expect(repository.fetchCount, greaterThan(fetchesBefore));
      expect(cubit.state.beacon.kind, BeaconKind.request);
      expect(cubit.state.beacon.title, _request().title);
    });
  });
}
