import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/features/beacon_room/domain/entity/beacon_room_invalidation.dart';
import 'package:tentura/features/beacon_room/domain/room_read_watermark_store.dart';
import 'package:tentura/features/forward/domain/entity/help_offer_event.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/use_case/my_work_case.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import 'my_work_test_support.dart';

void main() {
  group('MyWorkCase stream wiring', () {
    late FakeBeaconRepository beaconRepo;
    late FakeForwardRepository forwardRepo;
    late RoomReadWatermarkStore watermarkStore;
    late FakeBeaconRoomRepository roomRepo;

    setUp(() {
      beaconRepo = FakeBeaconRepository();
      forwardRepo = FakeForwardRepository();
      watermarkStore = RoomReadWatermarkStore.testing();
      roomRepo = FakeBeaconRoomRepository();
    });

    tearDown(() async {
      await beaconRepo.dispose();
      await forwardRepo.dispose();
      await watermarkStore.dispose();
      await roomRepo.dispose();
    });

    test('beaconChanges forwards beacon repository events', () async {
      final case_ = buildTestMyWorkCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        watermarkStore: watermarkStore,
        roomRepo: roomRepo,
      );
      final events = <RepositoryEvent<Beacon>>[];
      final sub = case_.beaconChanges.listen(events.add);

      final beacon = Beacon.empty.copyWith(id: 'b1');
      beaconRepo.emitChange(RepositoryEventInvalidate(beacon));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single, isA<RepositoryEventInvalidate<Beacon>>());
      expect(events.single.id, 'b1');

      await sub.cancel();
    });

    test('helpOfferChanges forwards forward repository events', () async {
      final case_ = buildTestMyWorkCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        watermarkStore: watermarkStore,
        roomRepo: roomRepo,
      );
      final events = <HelpOfferEvent>[];
      final sub = case_.helpOfferChanges.listen(events.add);

      forwardRepo.emitHelpOffer(const HelpOfferInvalidated('b2'));
      await Future<void>.delayed(Duration.zero);

      expect(events, hasLength(1));
      expect(events.single, isA<HelpOfferInvalidated>());
      expect(events.single.beaconId, 'b2');

      await sub.cancel();
    });

    test(
      'forwardCompleted forwards beacon ids from forward repository',
      () async {
        final case_ = buildTestMyWorkCase(
          beaconRepo: beaconRepo,
          forwardRepo: forwardRepo,
          watermarkStore: watermarkStore,
          roomRepo: roomRepo,
        );
        final ids = <String>[];
        final sub = case_.forwardCompleted.listen(ids.add);

        forwardRepo.emitForwardCompleted('b3');
        await Future<void>.delayed(Duration.zero);

        expect(ids, ['b3']);

        await sub.cancel();
      },
    );

    test('readWatermarkChanges forwards watermark store changes', () async {
      final case_ = buildTestMyWorkCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        watermarkStore: watermarkStore,
        roomRepo: roomRepo,
      );
      final ids = <String>[];
      final sub = case_.readWatermarkChanges.listen(ids.add);

      watermarkStore.observeReadThrough('b4', DateTime.utc(2026));
      await Future<void>.delayed(Duration.zero);

      expect(ids, ['b4']);

      await sub.cancel();
    });

    test('deskRelevantChanges forwards room invalidation beacon ids', () async {
      final case_ = buildTestMyWorkCase(
        beaconRepo: beaconRepo,
        forwardRepo: forwardRepo,
        watermarkStore: watermarkStore,
        roomRepo: roomRepo,
      );
      final ids = <String>[];
      final sub = case_.deskRelevantChanges.listen(ids.add);

      roomRepo.emitRoomInvalidation(
        const BeaconRoomInvalidation(
          beaconId: 'b5',
          entityType: BeaconRoomEntityType.coordinationItem,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(ids, ['b5']);

      await sub.cancel();
    });
  });

  group('MyWorkCubit stream invalidation', () {
    late FakeBeaconRepository beaconRepo;
    late FakeForwardRepository forwardRepo;
    late RoomReadWatermarkStore watermarkStore;
    late FakeBeaconRoomRepository roomRepo;
    late FakeMyWorkRepository repo;

    setUp(() {
      beaconRepo = FakeBeaconRepository();
      forwardRepo = FakeForwardRepository();
      watermarkStore = RoomReadWatermarkStore.testing();
      roomRepo = FakeBeaconRoomRepository();
      repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [
            Beacon.empty.copyWith(
              id: 'b1',
              status: BeaconStatus.open,
              updatedAt: DateTime(2025, 6),
            ),
          ],
          helpOfferedNonArchived: const [],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );
    });

    tearDown(() async {
      await beaconRepo.dispose();
      await forwardRepo.dispose();
      await watermarkStore.dispose();
      await roomRepo.dispose();
    });

    MyWorkCase buildCase() => buildTestMyWorkCase(
      repo: repo,
      beaconRepo: beaconRepo,
      forwardRepo: forwardRepo,
      watermarkStore: watermarkStore,
      roomRepo: roomRepo,
    );

    Future<void> waitForFetchCount(int expected) async {
      final deadline = DateTime.now().add(const Duration(seconds: 2));
      while (DateTime.now().isBefore(deadline)) {
        if (repo.fetchInitCallCount >= expected) {
          return;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      fail(
        'Expected at least $expected desk init fetches, '
        'got ${repo.fetchInitCallCount}.',
      );
    }

    test('beacon invalidate triggers desk refetch', () async {
      final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
      await cubit.stream.firstWhere((s) => s.isSuccess);
      expect(repo.fetchInitCallCount, 1);

      repo.initResult = (
        authoredNonArchived: [
          Beacon.empty.copyWith(
            id: 'b2',
            status: BeaconStatus.open,
            updatedAt: DateTime(2025, 7),
          ),
        ],
        helpOfferedNonArchived: const [],
        archivedCountHint: 0,
        lastItemDiscussionMessageAtByBeaconId: const {},
      );

      beaconRepo.emitChange(
        RepositoryEventInvalidate(Beacon.empty.copyWith(id: 'b1')),
      );
      await cubit.stream.firstWhere(
        (s) => s.isSuccess && s.nonArchivedCards.single.beaconId == 'b2',
      );
      expect(repo.fetchInitCallCount, 2);

      await cubit.close();
    });

    test('beacon delete removes card without full refetch', () async {
      final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
      await cubit.stream.firstWhere((s) => s.isSuccess);
      expect(cubit.state.nonArchivedCards, hasLength(1));
      final callsBefore = repo.fetchInitCallCount;

      beaconRepo.emitChange(
        RepositoryEventDelete(Beacon.empty.copyWith(id: 'b1')),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cubit.state.nonArchivedCards, isEmpty);
      expect(repo.fetchInitCallCount, callsBefore);

      await cubit.close();
    });

    test('help offer change triggers desk refetch', () async {
      final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
      await cubit.stream.firstWhere((s) => s.isSuccess);

      forwardRepo.emitHelpOffer(const HelpOfferCreated('b1'));
      await waitForFetchCount(2);
      expect(repo.fetchInitCallCount, 2);

      await cubit.close();
    });

    test('forward completed triggers desk refetch', () async {
      final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
      await cubit.stream.firstWhere((s) => s.isSuccess);

      forwardRepo.emitForwardCompleted('b1');
      await waitForFetchCount(2);
      expect(repo.fetchInitCallCount, 2);

      await cubit.close();
    });

    test('read watermark change triggers desk refetch', () async {
      final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
      await cubit.stream.firstWhere((s) => s.isSuccess);

      watermarkStore.observeReadThrough('b1', DateTime.utc(2026));
      await waitForFetchCount(2);
      expect(repo.fetchInitCallCount, 2);

      await cubit.close();
    });

    test(
      'desk-relevant room changes debounce per beacon before refetch',
      () async {
        final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
        await cubit.stream.firstWhere((s) => s.isSuccess);
        expect(repo.fetchInitCallCount, 1);

        roomRepo
          ..emitRoomInvalidation(
            const BeaconRoomInvalidation(
              beaconId: 'b1',
              entityType: BeaconRoomEntityType.roomMessage,
            ),
          )
          ..emitRoomInvalidation(
            const BeaconRoomInvalidation(
              beaconId: 'b1',
              entityType: BeaconRoomEntityType.coordinationItem,
            ),
          );

        await Future<void>.delayed(const Duration(milliseconds: 150));

        expect(repo.fetchInitCallCount, 2);

        await cubit.close();
      },
    );

    test('overlapping refetches keep only the latest result', () async {
      repo
        ..fetchInitDelay = const Duration(milliseconds: 50)
        ..initResult = (
          authoredNonArchived: [
            Beacon.empty.copyWith(
              id: 'stale',
              updatedAt: DateTime(2025),
            ),
          ],
          helpOfferedNonArchived: const [],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );

      final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
      await cubit.stream.firstWhere((s) => s.isSuccess);

      repo.initResult = (
        authoredNonArchived: [
          Beacon.empty.copyWith(
            id: 'fresh',
            status: BeaconStatus.open,
            updatedAt: DateTime(2025, 2),
          ),
        ],
        helpOfferedNonArchived: const [],
        archivedCountHint: 0,
        lastItemDiscussionMessageAtByBeaconId: const {},
      );

      beaconRepo
        ..emitChange(
          RepositoryEventInvalidate(Beacon.empty.copyWith(id: 'x1')),
        )
        ..emitChange(
          RepositoryEventInvalidate(Beacon.empty.copyWith(id: 'x2')),
        );

      await cubit.stream.firstWhere(
        (s) =>
            s.isSuccess && s.nonArchivedCards.any((c) => c.beaconId == 'fresh'),
      );
      expect(
        cubit.state.nonArchivedCards.map((c) => c.beaconId),
        ['fresh'],
      );
      expect(
        cubit.state.nonArchivedCards.single.kind,
        MyWorkCardKind.authoredActive,
      );

      await cubit.close();
    });

    Beacon authoredBeacon(String id, {DateTime? updatedAt}) =>
        Beacon.empty.copyWith(
          id: id,
          author: const Profile(id: 'u1'),
          status: BeaconStatus.open,
          updatedAt: updatedAt ?? DateTime(2025, 8),
        );

    test(
      'create event shows beacon in visibleCards before fetch completes',
      () async {
        repo.fetchInitDelay = const Duration(milliseconds: 100);
        final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
        await cubit.stream.firstWhere((s) => s.isSuccess);
        final callsAfterInit = repo.fetchInitCallCount;

        beaconRepo.emitChange(
          RepositoryEventCreate(authoredBeacon('b-new')),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          cubit.state.visibleCards.map((c) => c.beaconId),
          contains('b-new'),
        );
        expect(
          cubit.state.visibleCards
              .singleWhere((c) => c.beaconId == 'b-new')
              .kind,
          MyWorkCardKind.authoredActive,
        );
        expect(repo.fetchInitCallCount, greaterThan(callsAfterInit));

        await cubit.close();
      },
    );

    test('stale fetch preserves optimistic authored card', () async {
      final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
      await cubit.stream.firstWhere((s) => s.isSuccess);
      expect(cubit.state.nonArchivedCards.single.beaconId, 'b1');
      final callsAfterInit = repo.fetchInitCallCount;

      beaconRepo.emitChange(
        RepositoryEventCreate(authoredBeacon('b-new')),
      );
      await cubit.stream.firstWhere(
        (s) => s.nonArchivedCards.any((c) => c.beaconId == 'b-new'),
      );

      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(repo.fetchInitCallCount, greaterThan(callsAfterInit));
      expect(
        cubit.state.nonArchivedCards.map((c) => c.beaconId).toSet(),
        containsAll(['b1', 'b-new']),
      );

      await cubit.close();
    });

    test(
      'server fetch with pending beacon clears duplicate local row',
      () async {
        final cubit = MyWorkCubit(userId: 'u1', myWorkCase: buildCase());
        await cubit.stream.firstWhere((s) => s.isSuccess);

        repo.initResult = (
          authoredNonArchived: [
            Beacon.empty.copyWith(
              id: 'b1',
              status: BeaconStatus.open,
              updatedAt: DateTime(2025, 6),
            ),
            authoredBeacon('b-new', updatedAt: DateTime(2025, 9)),
          ],
          helpOfferedNonArchived: const [],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );

        beaconRepo.emitChange(
          RepositoryEventCreate(authoredBeacon('b-new')),
        );
        await cubit.stream.firstWhere(
          (s) =>
              s.isSuccess &&
              s.nonArchivedCards.map((c) => c.beaconId).toSet().containsAll({
                'b1',
                'b-new',
              }),
        );
        expect(cubit.state.nonArchivedCards, hasLength(2));

        await cubit.close();
      },
    );
  });
}
