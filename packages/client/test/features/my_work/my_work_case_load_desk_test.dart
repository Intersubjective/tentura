import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordination_responsibility.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_room_card_hints.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

import 'my_work_test_support.dart';

void main() {
  test('loadDeskInit returns enriched cards and archived count hint', () async {
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonArchived: [
          Beacon.empty.copyWith(
            id: 'b1',
            status: BeaconStatus.open,
            updatedAt: DateTime(2025, 6),
          ),
        ],
        helpOfferedNonArchived: const [],
        archivedCountHint: 2,
        lastItemDiscussionMessageAtByBeaconId: const {},
      );
    final case_ = buildTestMyWorkCase(repo: repo);

    final init = await case_.loadDeskInit(userId: 'u1');
    expect(init.nonArchivedCards, hasLength(1));
    expect(init.nonArchivedCards.single.kind, MyWorkCardKind.authoredActive);
    expect(init.archivedCountHint, 2);
    expect(init.finishedArchiveHintDismissed, isFalse);
  });

  test(
    'loadDeskInit returns finishedArchiveHintDismissed from prefs',
    () async {
      final prefs = FakeMyWorkDeskPreferencesPort()
        ..dismissedByUserId['u1'] = true;
      final case_ = buildTestMyWorkCase(deskPreferences: prefs);

      final init = await case_.loadDeskInit(userId: 'u1');
      expect(init.finishedArchiveHintDismissed, isTrue);
    },
  );

  test('loadDeskArchived returns archived cards', () async {
    final repo = FakeMyWorkRepository()
      ..archivedResult = (
        authoredArchived: [
          Beacon.empty.copyWith(
            id: 'c1',
            status: BeaconStatus.closed,
          ),
        ],
        helpOfferedArchived: const [],
      );
    final case_ = buildTestMyWorkCase(repo: repo);

    final archived = await case_.loadDeskArchived(userId: 'u1');
    expect(archived.archivedCards, hasLength(1));
    expect(archived.archivedCards.single.kind, MyWorkCardKind.authoredArchived);
  });

  test(
    'loadDeskInit fetches responsibility only for room-member cards',
    () async {
      final memberBeacon = Beacon.empty.copyWith(
        id: 'member',
        status: BeaconStatus.open,
        updatedAt: DateTime(2025, 6, 2),
      );
      final readOnlyBeacon = Beacon.empty.copyWith(
        id: 'readonly',
        status: BeaconStatus.open,
        updatedAt: DateTime(2025, 6),
      );
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: [memberBeacon],
          helpOfferedNonArchived: [
            (
              beacon: readOnlyBeacon,
              offerHelpMessage: 'ready to help',
              helpType: null,
              authorResponseType: null,
              forwarderSenders: const [],
              helpOfferRowUpdatedAt: DateTime(2025, 6),
              authorCoordinationUpdatedAt: null,
            ),
          ],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );
      final coordination = FakeCoordinationItemRepository()
        ..responsibilityByBeaconId = {
          'member': const CoordinationResponsibility(
            beaconId: 'member',
            askOpen: 2,
          ),
        };
      final hints = FakeRoomHints()
        ..hintsByBeaconId = const {
          'member': InboxRoomCardHints(isRoomMember: true, roomUnreadCount: 0),
          'readonly': InboxRoomCardHints(
            isRoomMember: false,
            roomUnreadCount: 0,
          ),
        };
      final case_ = buildTestMyWorkCase(
        repo: repo,
        coordinationRepo: coordination,
        roomHints: hints,
      );

      final init = await case_.loadDeskInit(userId: 'u1');

      expect(coordination.fetchResponsibilityBatchBeaconIds, ['member']);
      expect(
        init.nonArchivedCards.map((c) => c.beaconId),
        containsAll(['member', 'readonly']),
      );
      expect(
        init.nonArchivedCards
            .singleWhere((c) => c.beaconId == 'member')
            .youResponsibility
            ?.askOpen,
        2,
      );
      expect(
        init.nonArchivedCards
            .singleWhere((c) => c.beaconId == 'readonly')
            .youResponsibility,
        isNull,
      );
    },
  );

  test(
    'loadDeskInit skips responsibility loading for read-only cards',
    () async {
      final beacon = Beacon.empty.copyWith(
        id: 'readonly',
        status: BeaconStatus.open,
        updatedAt: DateTime(2025, 6),
      );
      final repo = FakeMyWorkRepository()
        ..initResult = (
          authoredNonArchived: const [],
          helpOfferedNonArchived: [
            (
              beacon: beacon,
              offerHelpMessage: 'ready to help',
              helpType: null,
              authorResponseType: null,
              forwarderSenders: const [],
              helpOfferRowUpdatedAt: DateTime(2025, 6),
              authorCoordinationUpdatedAt: null,
            ),
          ],
          archivedCountHint: 0,
          lastItemDiscussionMessageAtByBeaconId: const {},
        );
      final coordination = FakeCoordinationItemRepository()
        ..fetchResponsibilityBatchError = StateError('unauthorized');
      final hints = FakeRoomHints()
        ..hintsByBeaconId = const {
          'readonly': InboxRoomCardHints(
            isRoomMember: false,
            roomUnreadCount: 0,
          ),
        };
      final case_ = buildTestMyWorkCase(
        repo: repo,
        coordinationRepo: coordination,
        roomHints: hints,
      );

      final init = await case_.loadDeskInit(userId: 'u1');

      expect(coordination.fetchResponsibilityBatchBeaconIds, isNull);
      expect(init.nonArchivedCards, hasLength(1));
      expect(init.nonArchivedCards.single.beaconId, 'readonly');
      expect(init.nonArchivedCards.single.youResponsibility, isNull);
    },
  );
}
