import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/bloc/room_state.dart';

final _anchor = DateTime.utc(2026, 10, 21, 9);

void main() {
  final notices = <String, ({int? marker, int? kind})>{
    'joined': (marker: BeaconRoomSemanticMarker.participantJoined, kind: null),
    'left': (marker: BeaconRoomSemanticMarker.participantLeft, kind: null),
    'removed': (
      marker: BeaconRoomSemanticMarker.participantRemoved,
      kind: null,
    ),
    'hierarchy lifecycle': (
      marker: null,
      kind: BeaconRoomSystemMessageKind.hierarchyLifecycle,
    ),
    'child created': (
      marker: null,
      kind: BeaconRoomSystemMessageKind.childCreated,
    ),
    'closure story': (
      marker: null,
      kind: BeaconRoomSystemMessageKind.closureStory,
    ),
    'converted to Request': (
      marker: null,
      kind: BeaconRoomSystemMessageKind.convertedToRequest,
    ),
    'Post closed': (marker: null, kind: BeaconRoomSystemMessageKind.postClosed),
    'plan': (marker: null, kind: BeaconRoomSystemMessageKind.plan),
    'status changed': (
      marker: null,
      kind: BeaconRoomSystemMessageKind.statusChanged,
    ),
    'Request edited': (
      marker: null,
      kind: BeaconRoomSystemMessageKind.requestEdited,
    ),
  };

  group('Discussion unread messages exclude notices', () {
    for (final entry in notices.entries) {
      for (final anchor in <DateTime?>[_anchor, null]) {
        test(
          '${entry.key} notice does not count as unread ${anchor == null ? 'on a first visit' : 'after the last read point'}',
          () {
            final notice = RoomMessage(
              id: 'notice',
              beaconId: 'room',
              authorId: 'peer',
              body: '',
              createdAt: _anchor.add(const Duration(minutes: 1)),
              semanticMarker: entry.value.marker,
              systemMessageKind: entry.value.kind,
            );
            final onlyNotice = RoomState(
              myUserId: 'viewer',
              unreadAnchorAt: anchor,
              messages: [notice],
            );
            final withMessage = onlyNotice.copyWith(
              messages: [
                notice,
                RoomMessage(
                  id: 'message',
                  beaconId: 'room',
                  authorId: 'peer',
                  body: 'I can help',
                  createdAt: _anchor.add(const Duration(minutes: 2)),
                ),
              ],
            );
            final withSemanticMessages = onlyNotice.copyWith(
              messages: [
                notice,
                for (final (index, marker) in [
                  BeaconRoomSemanticMarker.baton,
                  BeaconRoomSemanticMarker.poll,
                  BeaconRoomSemanticMarker.factEdited,
                ].indexed)
                  RoomMessage(
                    id: 'semantic-$marker',
                    beaconId: 'room',
                    authorId: 'peer',
                    body: 'Member contribution',
                    createdAt: _anchor.add(Duration(minutes: index + 2)),
                    semanticMarker: marker,
                  ),
              ],
            );
            // Assert the negative case and the positive control together: a
            // predicate that discards every row must not satisfy this contract.
            expect(
              (
                onlyNotice.unreadCount,
                onlyNotice.firstUnreadMessageId,
                onlyNotice.firstUnreadIndex,
                withMessage.unreadCount,
                withMessage.firstUnreadMessageId,
                withMessage.firstUnreadIndex,
                withSemanticMessages.unreadCount,
                withSemanticMessages.firstUnreadMessageId,
              ),
              (
                0,
                null,
                -1,
                1,
                'message',
                1,
                3,
                'semantic-${BeaconRoomSemanticMarker.baton}',
              ),
            );
          },
        );
      }
    }
  });
}
