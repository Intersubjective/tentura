import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/features/inbox/domain/entity/inbox_item.dart';
import 'package:tentura/features/inbox/domain/enum.dart';
import 'package:tentura/features/inbox/ui/bloc/inbox_state.dart';

InboxItem _item({
  required String id,
  required double score,
  required DateTime latestForwardAt,
  DateTime? endAt,
}) =>
    InboxItem(
      beaconId: id,
      latestForwardAt: latestForwardAt,
      status: InboxItemStatus.needsMe,
      beacon: Beacon(
        id: id,
        title: id,
        score: score,
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        endAt: endAt,
      ),
    );

void main() {
  group('InboxState meritRank sort', () {
    test('orders needsMe by beacon score descending', () {
      final t = DateTime.utc(2026, 6, 1);
      final state = InboxState(
        sort: InboxSort.meritRank,
        items: [
          _item(id: 'low', score: 10, latestForwardAt: t),
          _item(id: 'high', score: 90, latestForwardAt: t),
          _item(id: 'mid', score: 50, latestForwardAt: t),
        ],
      );

      expect(state.needsMe.map((e) => e.beaconId).toList(), [
        'high',
        'mid',
        'low',
      ]);
    });

    test('treats missing beacon score as zero', () {
      final t = DateTime.utc(2026, 6, 1);
      final state = InboxState(
        sort: InboxSort.meritRank,
        items: [
          InboxItem(
            beaconId: 'no-beacon',
            latestForwardAt: t,
            status: InboxItemStatus.needsMe,
          ),
          _item(id: 'scored', score: 5, latestForwardAt: t),
        ],
      );

      expect(state.needsMe.map((e) => e.beaconId).toList(), [
        'scored',
        'no-beacon',
      ]);
    });
  });

  group('InboxState recent sort', () {
    test('orders by latestForwardAt descending', () {
      final state = InboxState(
        sort: InboxSort.recent,
        items: [
          _item(
            id: 'old',
            score: 99,
            latestForwardAt: DateTime.utc(2026, 5, 1),
          ),
          _item(
            id: 'new',
            score: 1,
            latestForwardAt: DateTime.utc(2026, 6, 1),
          ),
        ],
      );

      expect(state.needsMe.map((e) => e.beaconId).toList(), ['new', 'old']);
    });
  });

  group('InboxState deadline sort', () {
    test('orders by endAt ascending with null deadlines last', () {
      final t = DateTime.utc(2026, 6, 1);
      final state = InboxState(
        sort: InboxSort.deadline,
        items: [
          _item(
            id: 'none',
            score: 1,
            latestForwardAt: t,
          ),
          _item(
            id: 'later',
            score: 1,
            latestForwardAt: t,
            endAt: DateTime.utc(2026, 7, 1),
          ),
          _item(
            id: 'soon',
            score: 1,
            latestForwardAt: t,
            endAt: DateTime.utc(2026, 6, 15),
          ),
        ],
      );

      expect(state.needsMe.map((e) => e.beaconId).toList(), [
        'soon',
        'later',
        'none',
      ]);
    });
  });
}
