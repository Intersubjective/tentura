import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/my_work/domain/derive_my_work_cards.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_filter.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_sort.dart';

import 'my_work_test_support.dart';

Beacon _beacon(String id, {BeaconStatus status = BeaconStatus.open}) =>
    Beacon.empty.copyWith(
      id: id,
      updatedAt: DateTime(2025, 6, 1),
      status: status,
    );

void main() {
  group('buildNonArchivedViewModels obligations', () {
    test('gate-off path: empty obligations matches legacy two-input merge', () {
      final authored = [_beacon('a')];
      final without = buildNonArchivedViewModels(
        authoredNonArchived: authored,
        helpOfferedNonArchived: const [],
      );
      final withIgnored = buildNonArchivedViewModels(
        authoredNonArchived: authored,
        helpOfferedNonArchived: const [],
        obligationBeacons: const [],
      );
      expect(withIgnored, without);
      expect(
        without.single.sources,
        {MyWorkMembershipSource.authored},
      );
    });

    test('one obligation beacon yields one card', () {
      final obligation = (
        beacon: _beacon('obl'),
        viewerArchived: false,
      );
      final cards = buildNonArchivedViewModels(
        authoredNonArchived: const [],
        helpOfferedNonArchived: const [],
        obligationBeacons: [obligation, obligation],
      );
      expect(cards.length, 1);
      expect(cards.single.role, MyWorkCardRole.obligation);
      expect(cards.single.kind, MyWorkCardKind.obligationActive);
    });

    test('authored plus obligation merges to one card with both sources', () {
      final beacon = _beacon('both');
      final cards = buildNonArchivedViewModels(
        authoredNonArchived: [beacon],
        helpOfferedNonArchived: const [],
        obligationBeacons: [(beacon: beacon, viewerArchived: false)],
      );
      expect(cards.length, 1);
      expect(cards.single.role, MyWorkCardRole.authored);
      expect(cards.single.kind, MyWorkCardKind.authoredActive);
      expect(
        cards.single.sources,
        {
          MyWorkMembershipSource.authored,
          MyWorkMembershipSource.obligation,
        },
      );
    });

    test('obligation-only archived beacon passes active filter', () {
      final cards = buildNonArchivedViewModels(
        authoredNonArchived: const [],
        helpOfferedNonArchived: const [],
        obligationBeacons: [
          (beacon: _beacon('arch'), viewerArchived: true),
        ],
      );
      expect(cards.single.kind, MyWorkCardKind.obligationArchived);
      final visible = visibleMyWorkCardsForDesk(
        filter: MyWorkFilter.active,
        sort: MyWorkSort.recent,
        nonArchivedCards: cards,
        archivedCards: const [],
      );
      expect(visible.map((c) => c.beaconId), ['arch']);
    });
  });

  group('MyWorkCase activation gate', () {
    test('gate off ignores live obligations and passes empty ids to fetch', () async {
      final attentionRepo = StubAttentionRepository()
        ..obligationBeaconIds = {'would-appear'};
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [_beacon('keep')],
          helpOfferedNonArchived: const [],
          obligationBeacons: [
            (beacon: _beacon('would-appear'), viewerArchived: false),
          ],
          archivedCountHint: 0,
        );
      final case_ = buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
        obligationsGateEnabled: false,
      );

      final desk = await case_.loadDeskInit(userId: 'u1');
      expect(repo.lastObligationBeaconIds, isEmpty);
      expect(desk.nonArchivedCards.map((c) => c.beaconId), ['keep']);
      expect(
        desk.nonArchivedCards.every(
          (c) => !c.sources.contains(MyWorkMembershipSource.obligation),
        ),
        isTrue,
      );
    });

    test('gate on admits obligation-backed cards from fetch', () async {
      final attentionRepo = StubAttentionRepository()
        ..obligationBeaconIds = {'obl-only'};
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: const [],
          helpOfferedNonArchived: const [],
          obligationBeacons: [
            (beacon: _beacon('obl-only'), viewerArchived: false),
          ],
          archivedCountHint: 0,
        );
      final case_ = buildTestMyWorkCase(
        repo: repo,
        attentionRepository: attentionRepo,
        obligationsGateEnabled: true,
      );

      final desk = await case_.loadDeskInit(userId: 'u1');
      expect(repo.lastObligationBeaconIds, ['obl-only']);
      expect(desk.nonArchivedCards.single.beaconId, 'obl-only');
      expect(
        desk.nonArchivedCards.single.sources,
        {MyWorkMembershipSource.obligation},
      );
    });
  });
}
