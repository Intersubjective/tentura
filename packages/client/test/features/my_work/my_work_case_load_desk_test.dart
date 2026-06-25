import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon.dart';
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

  test('loadDeskInit returns finishedArchiveHintDismissed from prefs', () async {
    final prefs = FakeMyWorkDeskPreferencesPort()
      ..dismissedByUserId['u1'] = true;
    final case_ = buildTestMyWorkCase(deskPreferences: prefs);

    final init = await case_.loadDeskInit(userId: 'u1');
    expect(init.finishedArchiveHintDismissed, isTrue);
  });

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
}
