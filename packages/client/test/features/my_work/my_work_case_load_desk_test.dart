import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/features/my_work/domain/entity/my_work_card_view_model.dart';

import 'my_work_test_support.dart';

void main() {
  test('loadDeskInit returns enriched cards and closed id hints', () async {
    final repo = FakeMyWorkRepository()
      ..initResult = (
        authoredNonClosed: [
          Beacon.empty.copyWith(
            id: 'b1',
            lifecycle: BeaconLifecycle.open,
            updatedAt: DateTime(2025, 6, 1),
          ),
        ],
        helpOfferedNonClosed: const [],
        authoredClosedIds: const ['closed-1'],
        helpOfferedClosedIds: const ['closed-2'],
        lastItemDiscussionMessageAtByBeaconId: const {},
      );
    final case_ = buildTestMyWorkCase(repo);

    final init = await case_.loadDeskInit(userId: 'u1');
    expect(init.nonArchivedCards, hasLength(1));
    expect(init.nonArchivedCards.single.kind, MyWorkCardKind.authoredActive);
    expect(init.authoredClosedIdHints, ['closed-1']);
    expect(init.helpOfferedClosedIdHints, ['closed-2']);
  });

  test('loadDeskClosed returns archived cards', () async {
    final repo = FakeMyWorkRepository()
      ..closedResult = (
        authoredClosed: [
          Beacon.empty.copyWith(
            id: 'c1',
            lifecycle: BeaconLifecycle.closed,
          ),
        ],
        helpOfferedClosed: const [],
      );
    final case_ = buildTestMyWorkCase(repo);

    final closed = await case_.loadDeskClosed(userId: 'u1');
    expect(closed.archivedCards, hasLength(1));
    expect(closed.archivedCards.single.kind, MyWorkCardKind.authoredClosed);
  });
}
