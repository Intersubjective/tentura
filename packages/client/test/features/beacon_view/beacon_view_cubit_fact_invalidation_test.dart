// tentura-617.28 acceptance: factCard room invalidation -> targeted fact
// refresh, not a full request_detail reload. coordinationItem, participant
// and helpOffer invalidations intentionally keep today's full refresh.

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/beacon_threads/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_view/ui/bloc/beacon_view_cubit.dart';

import '../../ui/effect/fake_ui_effect_port.dart';
import 'beacon_view_case_test_support.dart';

const _myProfile = Profile(id: 'Uviewer', displayName: 'Viewer');
const _beaconId = 'Bfactinval01';

Beacon _readableBeacon() => Beacon(
  id: _beaconId,
  title: 'Fact invalidation beacon',
  createdAt: DateTime.utc(2026),
  updatedAt: DateTime.utc(2026),
  status: BeaconStatus.open,
  canReadContent: true,
  author: const Profile(id: 'Uauthor', displayName: 'Author'),
);

class _Harness {
  _Harness() {
    beaconRepo.fetchByIdHandler = (_) async => _readableBeacon();
    cubit = BeaconViewCubit(
      id: _beaconId,
      myProfile: _myProfile,
      beaconViewCase: buildTestBeaconViewCase(
        beaconRepo: beaconRepo,
        roomRepo: room,
        factCardsRepo: factCards,
      ),
      effects: FakeUiEffectPort(),
    );
  }

  final TrackingBeaconRepository beaconRepo = TrackingBeaconRepository();
  final FakeBeaconViewRoomRepository room = FakeBeaconViewRoomRepository();
  final FakeBeaconViewFactCardRepository factCards =
      FakeBeaconViewFactCardRepository();
  late final BeaconViewCubit cubit;

  Future<void> load() => _pumpUntilLoaded(cubit);

  void invalidate(BeaconRoomEntityType entityType) => room.emitRoomInvalidation(
    BeaconRoomInvalidation(beaconId: _beaconId, entityType: entityType),
  );

  Future<void> dispose() async {
    await cubit.close();
    await beaconRepo.dispose();
    await room.dispose();
  }
}

void main() {
  group('BeaconViewCubit factCard invalidation', () {
    test(
      'factCard room invalidation refreshes fact cards exactly once and '
      'triggers no full refresh',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.load();
        final fetchByIdAfterLoad = h.beaconRepo.fetchByIdCalls;
        final listCallsAfterLoad = h.factCards.listCalls;

        h.invalidate(BeaconRoomEntityType.factCard);
        await _settle();

        expect(
          h.factCards.listCalls,
          listCallsAfterLoad + 1,
          reason: 'factCard invalidation must refetch fact cards exactly once',
        );
        expect(
          h.beaconRepo.fetchByIdCalls,
          fetchByIdAfterLoad,
          reason:
              'factCard invalidation must not fall back to a full '
              'request_detail refresh',
        );
      },
    );

    for (final entityType in [
      BeaconRoomEntityType.coordinationItem,
      BeaconRoomEntityType.participant,
      BeaconRoomEntityType.helpOffer,
    ]) {
      test(
        '${entityType.name} room invalidation still triggers a full refresh '
        '(control)',
        () async {
          final h = _Harness();
          addTearDown(h.dispose);
          await h.load();
          final fetchByIdAfterLoad = h.beaconRepo.fetchByIdCalls;
          final listCallsAfterLoad = h.factCards.listCalls;

          h.invalidate(entityType);
          await _settle();

          // "Keep today's behaviour" means exactly one full refresh cycle
          // per invalidation, not merely "at least one" — a regression that
          // fires the gate twice (the same bug this bead fixes for factCard,
          // see the standalone and in-flight factCard tests above/below)
          // must fail these control cases too.
          expect(
            h.beaconRepo.fetchByIdCalls,
            fetchByIdAfterLoad + 1,
            reason:
                '${entityType.name} invalidation must keep today\'s full '
                'refresh behaviour: exactly one full refresh, not zero and '
                'not a duplicate',
          );
          // Today's full refresh always refetches fact cards too, alongside
          // the beacon, as part of its own enrichment Future.wait — exactly
          // once, not via a separate targeted fetch and not duplicated.
          expect(
            h.factCards.listCalls,
            listCallsAfterLoad + 1,
            reason:
                '${entityType.name} invalidation must refetch fact cards '
                'exactly once, embedded in the single full refresh',
          );
        },
      );
    }

    test(
      'factCard room invalidation arriving during an in-flight full refresh '
      'converges via the queued targeted refresh, without scheduling a '
      'second full refresh',
      () async {
        final h = _Harness();
        addTearDown(h.dispose);
        await h.load();
        final fetchByIdAfterLoad = h.beaconRepo.fetchByIdCalls;
        final listCallsAfterLoad = h.factCards.listCalls;

        // Hold the beacon fetch open so the fetch gate (`_fetchInProgress`)
        // stays true while the factCard invalidation below is delivered.
        final hold = Completer<void>();
        h.beaconRepo.fetchByIdHandler = (_) async {
          await hold.future;
          return _readableBeacon();
        };

        // A control entity type starts a full refresh and blocks on `hold`
        // inside it, holding the gate open.
        h.invalidate(BeaconRoomEntityType.participant);
        await _pumpUntilCallCount(
          () => h.beaconRepo.fetchByIdCalls,
          fetchByIdAfterLoad + 1,
        );
        expect(
          h.beaconRepo.fetchByIdCalls,
          fetchByIdAfterLoad + 1,
          reason:
              'the control invalidation must have started its full '
              'refresh (and be blocked mid-flight) before factCard arrives',
        );

        // factCard arrives while that full refresh is still in flight.
        h.invalidate(BeaconRoomEntityType.factCard);
        await _settle();

        // Release the held full refresh and let everything converge.
        hold.complete();
        await _settle();

        // Per the bead's documented fetch-gate contract, invalidations that
        // arrive during an in-flight full refresh queue into
        // `_pendingRoomTypes` and converge via `_runTargetedFetch` once the
        // gate clears — that path never re-enters `_runFetchWithGate`
        // (a second full refresh), which is reserved for `_fetchPending`
        // (another full-refresh-worthy invalidation). Once factCard is
        // routed like other targeted-only kinds, its queued convergence
        // must follow the same targeted path, not the full-refresh one.
        expect(
          h.beaconRepo.fetchByIdCalls,
          fetchByIdAfterLoad + 1,
          reason:
              'a factCard invalidation arriving while the gate is held must '
              'queue into the targeted refresh, not schedule a second full '
              'request_detail refresh',
        );
        expect(
          h.factCards.listCalls,
          listCallsAfterLoad + 2,
          reason:
              'fact cards must still refetch once for the in-flight full '
              "refresh's own enrichment and once more for the queued "
              'factCard invalidation once the gate clears',
        );
      },
    );
  });
}

Future<void> _pumpUntilLoaded(BeaconViewCubit cubit) => _pumpUntil(
  cubit.stream,
  () => cubit.state.beaconContextLoaded,
);

Future<void> _pumpUntil(
  Stream<BeaconViewState> stream,
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  if (condition()) return;
  await stream.timeout(timeout).firstWhere((_) => condition());
}

/// Drains chained microtasks/zero-duration timers deterministically instead
/// of racing a wall-clock quiet period, following this repo's convention
/// (e.g. `test/features/graph/graph_cubit_genealogy_test.dart`). The
/// invalidation-handling chain under test can recurse through the fetch
/// gate twice (full refresh -> queued follow-up), so this uses a larger
/// `times` than the repo's typical `times: 5` to give that extra depth room
/// to fully unwind before assertions run.
Future<void> _settle() => pumpEventQueue(times: 30);

/// Waits until [count] reaches [target], for scenarios that must observe an
/// in-flight call (one that is synchronously counted but then blocks on an
/// uncompleted `Completer`) before proceeding — a plain [_settle] cannot
/// substitute here because nothing else will ever unblock it.
Future<void> _pumpUntilCallCount(
  int Function() count,
  int target, {
  Duration timeout = const Duration(seconds: 2),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (count() < target) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'call count did not reach $target within $timeout',
      );
    }
    await Future<void>.delayed(Duration.zero);
  }
}
