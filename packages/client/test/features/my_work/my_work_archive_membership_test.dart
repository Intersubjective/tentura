import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_sort.dart';
import 'package:tentura/features/my_work/ui/bloc/my_work_cubit.dart';

import 'my_work_test_support.dart';

Beacon _beacon(
  String id, {
  BeaconStatus status = BeaconStatus.closed,
}) =>
    Beacon.empty.copyWith(
      id: id,
      updatedAt: DateTime(2025, 6, 1),
      status: status,
    );

void main() {
  group('myWorkCardAfterArchiveRevocation', () {
    test('obligation-only card stays archived in place', () {
      final card = MyWorkCardViewModel(
        beaconId: 'obl',
        role: MyWorkCardRole.obligation,
        kind: MyWorkCardKind.obligationActive,
        beacon: _beacon('obl', status: BeaconStatus.open),
        sources: {MyWorkMembershipSource.obligation},
      );
      final next = myWorkCardAfterArchiveRevocation(card);
      expect(next, isNotNull);
      expect(next!.viewerArchived, isTrue);
      expect(next.kind, MyWorkCardKind.obligationArchived);
      expect(next.sources, {MyWorkMembershipSource.obligation});
    });

    test('authored-only card is removed from desk', () {
      final card = buildNonArchivedViewModels(
        authoredNonArchived: [_beacon('a')],
        helpOfferedNonArchived: const [],
      ).single;
      expect(myWorkCardAfterArchiveRevocation(card), isNull);
    });
  });

  group('MyWorkCubit archive membership', () {
    test('archive obligation-backed authored card keeps row marked archived', () async {
      final beacon = _beacon('both');
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [beacon],
          helpOfferedNonArchived: const [],
          obligationBeacons: [(beacon: beacon, viewerArchived: false)],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );
      final attentionRepo = StubAttentionRepository()
        ..obligationBeaconIds = {'both'};
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(
          repo: repo,
          attentionRepository: attentionRepo,
          obligationsGateEnabled: true,
        ),
      );
      await cubit.stream.firstWhere((s) => s.isSuccess);

      expect(cubit.state.nonArchivedCards.single.sources, {
        MyWorkMembershipSource.authored,
        MyWorkMembershipSource.obligation,
      });

      await cubit.archiveBeacon('both');

      expect(cubit.state.nonArchivedCards.length, 1);
      final card = cubit.state.nonArchivedCards.single;
      expect(card.beaconId, 'both');
      expect(card.viewerArchived, isTrue);
      expect(card.sources, {MyWorkMembershipSource.obligation});
      expect(card.kind, MyWorkCardKind.obligationArchived);
      expect(cubit.state.archivedCountHint, 1);

      await cubit.close();
    });

    test('archive twice increments archivedCountHint once', () async {
      final beacon = _beacon('both');
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [beacon],
          helpOfferedNonArchived: const [],
          obligationBeacons: [(beacon: beacon, viewerArchived: false)],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(
          repo: repo,
          obligationsGateEnabled: true,
          attentionRepository: StubAttentionRepository()
            ..obligationBeaconIds = {'both'},
        ),
      );
      await cubit.stream.firstWhere((s) => s.isSuccess);

      await cubit.archiveBeacon('both');
      await cubit.archiveBeacon('both');

      expect(cubit.state.archivedCountHint, 1);

      await cubit.close();
    });

    test('settling last obligation removes archived obligation-only card', () async {
      final beacon = _beacon('both');
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [beacon],
          helpOfferedNonArchived: const [],
          obligationBeacons: [(beacon: beacon, viewerArchived: false)],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );
      final attentionRepo = StubAttentionRepository()
        ..obligationBeaconIds = {'both'};
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(
          repo: repo,
          attentionRepository: attentionRepo,
          obligationsGateEnabled: true,
        ),
      );
      await cubit.stream.firstWhere((s) => s.isSuccess);
      await cubit.archiveBeacon('both');
      expect(cubit.state.nonArchivedCards, isNotEmpty);

      attentionRepo.obligationBeaconIds = {};
      repo.initResult = (
        authoredNonArchived: const [],
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
        archivedCountHint: 1,
        lastItemDiscussionMessageAtByBeaconId: const {},
      );
      await cubit.fetch(showLoading: false);
      expect(cubit.state.isSuccess, isTrue);
      expect(cubit.state.nonArchivedCards, isEmpty);

      await cubit.close();
    });

    test('reload reproduces archived obligation-backed card', () async {
      final beacon = _beacon('both');
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [beacon],
          helpOfferedNonArchived: const [],
          obligationBeacons: [(beacon: beacon, viewerArchived: false)],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );
      final attentionRepo = StubAttentionRepository()
        ..obligationBeaconIds = {'both'};
      final cubit = MyWorkCubit(
        userId: 'user-1',
        myWorkCase: buildTestMyWorkCase(
          repo: repo,
          attentionRepository: attentionRepo,
          obligationsGateEnabled: true,
        ),
      );
      await cubit.stream.firstWhere((s) => s.isSuccess);
      await cubit.archiveBeacon('both');

      repo.initResult = (
        authoredNonArchived: const [],
        helpOfferedNonArchived: const [],
        obligationBeacons: [(beacon: beacon, viewerArchived: true)],
        archivedCountHint: 1,
        lastItemDiscussionMessageAtByBeaconId: const {},
      );
      await cubit.fetch(showLoading: false);
      expect(cubit.state.isSuccess, isTrue);

      final card = cubit.state.nonArchivedCards.single;
      expect(card.viewerArchived, isTrue);
      expect(card.sources, {MyWorkMembershipSource.obligation});
      final visible = visibleMyWorkCardsForDesk(
        filter: MyWorkFilter.active,
        sort: MyWorkSort.recent,
        nonArchivedCards: cubit.state.nonArchivedCards,
        archivedCards: const [],
      );
      expect(visible.map((c) => c.beaconId), ['both']);

      await cubit.close();
    });
  });
}
