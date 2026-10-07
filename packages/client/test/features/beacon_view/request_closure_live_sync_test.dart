import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura/data/service/remote_api_client/realtime_socket.dart';
import 'package:tentura/data/service/remote_api_service.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/port/realtime_sync_port.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';
import 'package:tentura/features/closure/domain/entity/beacon_close_result.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';

import '../../support/test_realtime_sync.dart';
import '../../ui/effect/fake_ui_effect_port.dart';
import '../my_work/my_work_test_support.dart';
import 'beacon_view_case_test_support.dart';

const _beaconId = 'Brequestclose';
const _author = Profile(id: 'Urequestauthor', displayName: 'Author');

Beacon _request(BeaconStatus status) => Beacon(
  id: _beaconId,
  title: 'A Request to close',
  author: _author,
  status: status,
  createdAt: DateTime.utc(2026, 10, 7),
  updatedAt: DateTime.utc(2026, 10, 7),
);

class _SuccessfulCloseRepository extends FakeBeaconViewClosureRepository {
  final closedIds = <String>[];

  @override
  Future<BeaconCloseResult> beaconClose({required String beaconId}) async {
    closedIds.add(beaconId);
    return BeaconCloseResult(
      beaconId: beaconId,
      state: BeaconStatus.closed.smallintValue,
    );
  }
}

// Keep the production realtime-to-invalidation subscription and
// refreshAndNotify implementation. Only server reads are replaced.
class _LiveBeaconRepository extends BeaconRepository {
  _LiveBeaconRepository(RealtimeSyncPort realtime)
    : this._(
        RemoteApiService(
          const Env(),
          const WebSocketClientRealtimeSocketFactory(),
        ),
        realtime,
      );

  _LiveBeaconRepository._(RemoteApiService remote, RealtimeSyncPort realtime)
    : _unusedRemote = remote,
      super(remote, realtime);

  final RemoteApiService _unusedRemote;

  Beacon serverRequest = _request(BeaconStatus.open);
  int fetchByIdCalls = 0;

  @override
  Future<Beacon> fetchBeaconById(String id) async {
    expect(id, _beaconId);
    fetchByIdCalls++;
    return serverRequest;
  }

  @override
  Future<List<Profile>> fetchAdmittedHelpers(String id) async => const [];

  @override
  Future<void> dispose() async {
    await super.dispose();
    await _unusedRemote.close();
  }
}

void main() {
  group('Request closure stays live for the author', () {
    test(
      'successful close applies closed status despite a stale detail read',
      () async {
        final realtime = buildTestRealtimeSync();
        final beaconRepo = _LiveBeaconRepository(realtime.port);
        final closureRepo = _SuccessfulCloseRepository();
        final effects = FakeUiEffectPort();
        final view = BeaconViewCubit(
          id: _beaconId,
          myProfile: _author,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: beaconRepo,
            closureRepo: closureRepo,
            realtimeSyncCase: realtime.case_,
          ),
          effects: effects,
        );
        addTearDown(() async {
          await view.close();
          await beaconRepo.dispose();
          await realtime.port.dispose();
        });
        await view.stream
            .firstWhere((state) => state.beaconContextLoaded)
            .timeout(const Duration(seconds: 2));
        expect(view.state.beacon.status, BeaconStatus.open);

        // The close result is authoritative even if the detail endpoint still
        // serves the pre-close snapshot. No reload or manual fetch follows.
        final result = await view.closeBeacon(
          expectedRequiresReviewWindow: false,
        );
        await pumpEventQueue();

        expect(closureRepo.closedIds, [_beaconId]);
        expect(result, isNotNull);
        expect(result!.state, BeaconStatus.closed.smallintValue);
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
        expect(view.state.isLoading, isFalse);
        expect(view.state.beacon.status, BeaconStatus.closed);
      },
    );

    test(
      'successful author close updates My Work without a realtime hint',
      () async {
        final realtime = buildTestRealtimeSync();
        final beaconRepo = _LiveBeaconRepository(realtime.port);
        final closureRepo = _SuccessfulCloseRepository();
        final deskRepo = FakeMyWorkRepository()
          ..initResult = (
            authoredNonArchived: [beaconRepo.serverRequest],
            helpOfferedNonArchived: const [],
            obligationBeacons: const [],
            archivedCountHint: 0,
          );
        final view = BeaconViewCubit(
          id: _beaconId,
          myProfile: _author,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: beaconRepo,
            closureRepo: closureRepo,
            realtimeSyncCase: realtime.case_,
          ),
          effects: FakeUiEffectPort(),
        );
        final desk = MyWorkCubit(
          userId: _author.id,
          myWorkCase: buildTestMyWorkCase(
            repo: deskRepo,
            beaconRepo: beaconRepo,
            attentionRepository: StubAttentionRepository(),
            realtimeSyncCase: realtime.case_,
          ),
        );
        addTearDown(() async {
          await view.close();
          await desk.close();
          await beaconRepo.dispose();
          await realtime.port.dispose();
        });
        await Future.wait([
          view.stream.firstWhere((state) => state.beaconContextLoaded),
          desk.stream.firstWhere((state) => state.attentionLoaded),
        ]).timeout(const Duration(seconds: 2));
        expect(view.state.beacon.status, BeaconStatus.open);
        expect(
          desk.state.nonArchivedCards.single.beacon.status,
          BeaconStatus.open,
        );

        // Both surfaces share the production repository event stream. The
        // mutation reports closed, while detail/list reads remain stale; no
        // external realtime hint or manual fetch is supplied by the test.
        final result = await view.closeBeacon(
          expectedRequiresReviewWindow: false,
        );
        await pumpEventQueue(times: 30);
        expect(closureRepo.closedIds, [_beaconId]);
        expect(result, isNotNull);
        expect(result!.state, BeaconStatus.closed.smallintValue);
        final card = [
          ...desk.state.nonArchivedCards,
          ...desk.state.archivedCards,
        ].singleWhere((card) => card.beaconId == _beaconId);
        expect(card.beacon.status, BeaconStatus.closed);
        expect(view.state.beacon.status, BeaconStatus.closed);
      },
    );

    test(
      'matching beacon realtime hint refreshes the open Request and My Work card',
      () async {
        final realtime = buildTestRealtimeSync();
        final beaconRepo = _LiveBeaconRepository(realtime.port);
        final deskRepo = FakeMyWorkRepository()
          ..initResult = (
            authoredNonArchived: [beaconRepo.serverRequest],
            helpOfferedNonArchived: const [],
            obligationBeacons: const [],
            archivedCountHint: 0,
          );
        final effects = FakeUiEffectPort();
        final view = BeaconViewCubit(
          id: _beaconId,
          myProfile: _author,
          beaconViewCase: buildTestBeaconViewCase(
            beaconRepo: beaconRepo,
            realtimeSyncCase: realtime.case_,
          ),
          effects: effects,
        );
        final desk = MyWorkCubit(
          userId: _author.id,
          myWorkCase: buildTestMyWorkCase(
            repo: deskRepo,
            beaconRepo: beaconRepo,
            attentionRepository: StubAttentionRepository(),
            realtimeSyncCase: realtime.case_,
          ),
        );
        addTearDown(() async {
          await view.close();
          await desk.close();
          await beaconRepo.dispose();
          await realtime.port.dispose();
        });
        await Future.wait([
          view.stream.firstWhere((state) => state.beaconContextLoaded),
          desk.stream.firstWhere((state) => state.attentionLoaded),
        ]).timeout(const Duration(seconds: 2));
        expect(view.state.beacon.status, BeaconStatus.open);
        expect(desk.state.nonArchivedCards.single.beaconId, _beaconId);
        expect(
          desk.state.nonArchivedCards.single.beacon.status,
          BeaconStatus.open,
        );
        await pumpEventQueue(times: 30);
        final viewFetches = beaconRepo.fetchByIdCalls;

        realtime.port.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.beacon,
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
            aggregateId: 'Botherrequest',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await pumpEventQueue(times: 30);
        expect(
          beaconRepo.fetchByIdCalls,
          viewFetches,
          reason: 'A hint for another Request must not refetch the open view',
        );
        expect(view.state.beacon.status, BeaconStatus.open);
        final deskFetches = deskRepo.fetchInitCallCount;

        beaconRepo.serverRequest = beaconRepo.serverRequest.copyWith(
          status: BeaconStatus.closed,
          updatedAt: DateTime.utc(2026, 10, 7, 12),
        );
        deskRepo.initResult = (
          authoredNonArchived: [beaconRepo.serverRequest],
          helpOfferedNonArchived: const [],
          obligationBeacons: const [],
          archivedCountHint: 0,
        );
        // The production repository projects this hint onto its invalidation
        // stream; neither cubit is manually refreshed.
        final viewClosed = view.stream
            .firstWhere((state) => state.beacon.status == BeaconStatus.closed)
            .timeout(const Duration(seconds: 2));
        final deskClosed = desk.stream
            .firstWhere(
              (state) =>
                  [...state.nonArchivedCards, ...state.archivedCards].any(
                    (card) =>
                        card.beaconId == _beaconId &&
                        card.beacon.status == BeaconStatus.closed,
                  ),
            )
            .timeout(const Duration(seconds: 2));
        realtime.port.emitChange(
          const RealtimeEntityChange(
            kind: RealtimeEntityKind.beacon,
            operation: RealtimeOperation.update,
            source: RealtimeChangeSource.serverInvalidation,
            aggregateId: _beaconId,
          ),
        );
        await Future.wait([viewClosed, deskClosed]);
        await pumpEventQueue(times: 30);

        expect(deskRepo.fetchInitCallCount, greaterThan(deskFetches));
        final card = [
          ...desk.state.nonArchivedCards,
          ...desk.state.archivedCards,
        ].singleWhere((card) => card.beaconId == _beaconId);
        expect(card.beaconId, _beaconId);
        expect(card.beacon.status, BeaconStatus.closed);
        expect(effects.emitted.whereType<ShowError>(), isEmpty);
        expect(
          beaconRepo.fetchByIdCalls,
          greaterThan(viewFetches),
          reason: 'The matching beacon hint must refetch the open Request',
        );
        expect(view.state.beacon.status, BeaconStatus.closed);
      },
    );
  });
}
