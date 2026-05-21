import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/coordination_room_navigation.dart';

CoordinationItem _item(CoordinationItemKind kind) => CoordinationItem(
      id: 'item1',
      beaconId: 'beacon1',
      kind: kind,
      status: CoordinationItemStatus.open,
      creatorId: 'user1',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  group('planItemSuppressesItemDiscussion', () {
    final plan = _item(CoordinationItemKind.plan);
    final ask = _item(CoordinationItemKind.ask);
    final blocker = _item(CoordinationItemKind.blocker);

    test('all plan items suppress item discussion navigation', () {
      for (final kind in CoordinationItemEventKind.values) {
        expect(
          planItemSuppressesItemDiscussion(plan),
          isTrue,
          reason: 'plan + $kind',
        );
      }
    });

    test('non-plan items keep item discussion navigation', () {
      expect(planItemSuppressesItemDiscussion(ask), isFalse);
      expect(planItemSuppressesItemDiscussion(blocker), isFalse);
    });
  });
}
