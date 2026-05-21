import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_tile.dart';

RoomMessage _msg({
  required String id,
  String? linkedItemId,
  int? linkedEventKind,
  String? systemPayloadJson,
  String? linkedItemLinkedMessageId,
  int? linkedItemKind,
  int? linkedItemStatus,
  String? linkedItemCreatorId,
}) =>
    RoomMessage(
      id: id,
      beaconId: 'b1',
      authorId: 'u1',
      body: 'hello',
      createdAt: DateTime.utc(2026),
      linkedItemId: linkedItemId,
      linkedEventKind: linkedEventKind,
      systemPayloadJson: systemPayloadJson,
      linkedItemLinkedMessageId: linkedItemLinkedMessageId,
      linkedItemKind: linkedItemKind,
      linkedItemStatus:
          linkedItemStatus ?? CoordinationItemStatus.open.value,
      linkedItemCreatorId: linkedItemCreatorId,
      linkedItemCreatedAt: DateTime.utc(2026),
      linkedItemUpdatedAt: DateTime.utc(2026),
    );

void main() {
  group('isCoordinationTimelineNotifyRow', () {
    test('notify row with sourceMessageId is timeline row', () {
      expect(
        RoomMessageTile.isCoordinationTimelineNotifyRow(
          _msg(
            id: 'notify',
            linkedItemId: 'item1',
            linkedEventKind: CoordinationItemEventKind.resolved.value,
            systemPayloadJson: '{"sourceMessageId":"source"}',
            linkedItemKind: CoordinationItemKind.ask.value,
          ),
        ),
        isTrue,
      );
    });

    test('source message is not a timeline notify row', () {
      expect(
        RoomMessageTile.isCoordinationTimelineNotifyRow(
          _msg(
            id: 'source',
            linkedItemId: 'item1',
            linkedEventKind: CoordinationItemEventKind.created.value,
            linkedItemLinkedMessageId: 'source',
            linkedItemKind: CoordinationItemKind.ask.value,
          ),
        ),
        isFalse,
      );
    });

    test('isPromotedSourceMessage detects source', () {
      final m = _msg(
        id: 'source',
        linkedItemId: 'item1',
        linkedEventKind: CoordinationItemEventKind.created.value,
        linkedItemLinkedMessageId: 'source',
        linkedItemKind: CoordinationItemKind.ask.value,
        linkedItemCreatorId: 'u1',
      );
      expect(m.isPromotedSourceMessage, isTrue);
      expect(RoomMessageTile.showLifecycleFooter(m), isTrue);
    });

    test('linkedCoordinationItem includes linkedMessageId', () {
      final m = _msg(
        id: 'source',
        linkedItemId: 'item1',
        linkedEventKind: CoordinationItemEventKind.created.value,
        linkedItemLinkedMessageId: 'source',
        linkedItemKind: CoordinationItemKind.ask.value,
        linkedItemCreatorId: 'u1',
      );
      expect(m.linkedCoordinationItem?.linkedMessageId, 'source');
    });
  });
}
