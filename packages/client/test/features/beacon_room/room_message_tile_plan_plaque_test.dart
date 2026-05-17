import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';

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
  group('planLifecyclePlaqueSuppressesDiscussion', () {
    final plan = _item(CoordinationItemKind.plan);
    final ask = _item(CoordinationItemKind.ask);
    final blocker = _item(CoordinationItemKind.blocker);

    test('plan lifecycle events suppress discussion navigation', () {
      for (final kind in [
        CoordinationItemEventKind.created,
        CoordinationItemEventKind.updated,
        CoordinationItemEventKind.superseded,
      ]) {
        expect(
          planLifecyclePlaqueSuppressesDiscussion(plan, kind),
          isTrue,
          reason: 'plan + $kind',
        );
      }
    });

    test('plan resolved and non-plan items keep discussion navigation', () {
      expect(
        planLifecyclePlaqueSuppressesDiscussion(
          plan,
          CoordinationItemEventKind.resolved,
        ),
        isFalse,
      );
      expect(
        planLifecyclePlaqueSuppressesDiscussion(
          plan,
          CoordinationItemEventKind.accepted,
        ),
        isFalse,
      );
      expect(
        planLifecyclePlaqueSuppressesDiscussion(
          ask,
          CoordinationItemEventKind.created,
        ),
        isFalse,
      );
      expect(
        planLifecyclePlaqueSuppressesDiscussion(
          blocker,
          CoordinationItemEventKind.created,
        ),
        isFalse,
      );
    });
  });
}
