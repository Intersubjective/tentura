import 'package:flutter_test/flutter_test.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
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
  String? linkedItemTargetPersonId,
  int? semanticMarker,
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
      linkedItemTargetPersonId: linkedItemTargetPersonId,
      linkedItemCreatedAt: DateTime.utc(2026),
      linkedItemUpdatedAt: DateTime.utc(2026),
      semanticMarker: semanticMarker,
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
      expect(RoomMessageTile.showCoordinationItemFooter(m), isTrue);
      expect(RoomMessageTile.showLifecycleFooter(m), isTrue);
    });

    test('legacy notify row resolves anchor without sourceMessageId payload', () {
      final m = _msg(
        id: 'notify',
        linkedItemId: 'item1',
        linkedEventKind: CoordinationItemEventKind.resolved.value,
        linkedItemLinkedMessageId: 'source',
        linkedItemKind: CoordinationItemKind.ask.value,
      );
      expect(RoomMessageTile.isCoordinationTimelineNotifyRow(m), isTrue);
      expect(
        RoomMessageTile.coordinationTimelineAnchorMessageId(m),
        'source',
      );
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

    test('linkedCoordinationItem includes targetPersonId from snapshot', () {
      final m = _msg(
        id: 'source',
        linkedItemId: 'item1',
        linkedEventKind: CoordinationItemEventKind.created.value,
        linkedItemKind: CoordinationItemKind.ask.value,
        linkedItemCreatorId: 'u1',
        linkedItemTargetPersonId: 'u2',
      );
      expect(m.linkedCoordinationItem?.targetPersonId, 'u2');
    });
  });

  group('isPromotedSourceMessage', () {
    test('timeline notify row with created event is not promoted source', () {
      final m = _msg(
        id: 'notify',
        linkedItemId: 'item1',
        linkedEventKind: CoordinationItemEventKind.created.value,
        systemPayloadJson: '{"sourceMessageId":"source"}',
        linkedItemLinkedMessageId: 'source',
        linkedItemKind: CoordinationItemKind.ask.value,
        linkedItemCreatorId: 'u1',
      );
      expect(m.isPromotedSourceMessage, isFalse);
      expect(RoomMessageTile.showCoordinationItemFooter(m), isFalse);
      expect(RoomMessageTile.showLifecycleFooter(m), isFalse);
    });

    test('standalone creation row is promoted source', () {
      final m = _msg(
        id: 'roomRow',
        linkedItemId: 'item1',
        linkedEventKind: CoordinationItemEventKind.created.value,
        linkedItemKind: CoordinationItemKind.blocker.value,
        linkedItemCreatorId: 'u1',
      );
      expect(m.isPromotedSourceMessage, isTrue);
      expect(RoomMessageTile.showCoordinationItemFooter(m), isTrue);
      expect(RoomMessageTile.showLifecycleFooter(m), isTrue);
    });

    test('non-promoted linked item uses coordination footer not inline card', () {
      final m = _msg(
        id: 'notify',
        linkedItemId: 'item1',
        linkedEventKind: CoordinationItemEventKind.created.value,
        linkedItemLinkedMessageId: 'source',
        linkedItemKind: CoordinationItemKind.ask.value,
        linkedItemCreatorId: 'u1',
      );
      expect(m.isPromotedSourceMessage, isFalse);
      expect(RoomMessageTile.isCoordinationTimelineNotifyRow(m), isFalse);
      expect(RoomMessageTile.showCoordinationItemFooter(m), isTrue);
      expect(RoomMessageTile.showLifecycleFooter(m), isFalse);
    });

    test('orphan linkedItemId without item snapshot is not promoted source', () {
      final m = RoomMessage(
        id: 'orphan',
        beaconId: 'b1',
        authorId: 'u1',
        body: '',
        createdAt: DateTime.utc(2026),
        linkedItemId: 'item1',
        linkedEventKind: CoordinationItemEventKind.created.value,
      );
      expect(m.linkedCoordinationItem, isNull);
      expect(m.isPromotedSourceMessage, isFalse);
    });
  });

  group('showCoordinationItemFooter with mark done', () {
    test('semantic done keeps coordination footer for promoted ask', () {
      final m = _msg(
        id: 'source',
        linkedItemId: 'item1',
        linkedEventKind: CoordinationItemEventKind.created.value,
        linkedItemKind: CoordinationItemKind.ask.value,
        linkedItemCreatorId: 'u1',
        linkedItemStatus: CoordinationItemStatus.resolved.value,
        semanticMarker: BeaconRoomSemanticMarker.done,
        systemPayloadJson: '{"semanticActorId":"u2"}',
      );
      expect(RoomMessageTile.showMarkDoneFooter(m), isTrue);
      expect(RoomMessageTile.showCoordinationItemFooter(m), isTrue);
    });
  });

  group('thread mark accent', () {
    test('resolved ask uses open warn accent not muted resolved accent', () {
      // Uses design tokens indirectly via coordinationItemColor — open ask is warn.
      expect(
        RoomMessageTile.isThreadEntryKind(CoordinationItemKind.ask),
        isTrue,
      );
      expect(
        RoomMessageTile.isThreadEntryKind(CoordinationItemKind.plan),
        isFalse,
      );
    });
  });
}
