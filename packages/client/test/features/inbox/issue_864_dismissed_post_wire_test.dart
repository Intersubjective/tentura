import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon_threads/data/repository/beacon_room_hints_repository.dart';
import 'package:tentura/features/inbox/data/repository/inbox_repository.dart';
import 'package:tentura/features/inbox/domain/enum.dart';

import '../../support/remote_wire_harness.dart';

const _beaconId = 'Bdismissedpost1';
const _userId = 'Uviewer000001';
const _at = '2026-10-30T12:00:00.000Z';

Map<String, dynamic> _beaconWire({required int kind}) => {
  '__typename': 'beacon',
  'id': _beaconId,
  'cover_source': 0,
  'title': '',
  'description': '',
  'needs': '',
  'created_at': _at,
  'updated_at': _at,
  'status': 0,
  'tags': '',
  'beacon_images': <dynamic>[],
  'author': {
    '__typename': 'user',
    'id': 'Ualice0000001',
    'display_name': 'Alice GQ2',
    'description': '',
  },
  'help_offers_aggregate': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'active_help_offers': <dynamic>[],
  'participant_help_offers': <dynamic>[],
  'unanswered_help_offers': {
    '__typename': 'beacon_help_offer_aggregate',
    'aggregate': null,
  },
  'admitted_helpers_aggregate': {
    '__typename': 'beacon_admitted_helper_aggregate',
    'aggregate': null,
  },
  'is_discoverable': false,
  'kind': kind,
  'forward_policy': 1,
  'last_activity_at': _at,
  'post_root_message_id': 'Mroot00000001',
  'viewer_can_forward': true,
  'can_read_content': true,
  'can_read_involvement': true,
  'can_read_admitted_helpers': true,
  'my_forward_edges': <dynamic>[],
};

Map<String, dynamic> _inboxRowWire({required int kind}) => {
  '__typename': 'inbox_item',
  'beacon_id': _beaconId,
  'context': '',
  'forward_count': 0,
  'latest_forward_at': _at,
  'latest_note_preview': '',
  'status': 2,
  'private_note': '',
  'rejection_message': '',
  'before_response_terminal_at': null,
  'tombstone_dismissed_at': null,
  'inbox_provenance_data': null,
  'beacon': _beaconWire(kind: kind),
};

void main() {
  test(
    'InboxFetch maps a rejected Post with kind 1 through the repository',
    () async {
      await withRemoteWire(
        {
          'InboxFetch': {
            '__typename': 'query_root',
            'inbox_item': [_inboxRowWire(kind: 1)],
          },
          'InboxRoomContextBatch': {
            '__typename': 'query_root',
            'InboxRoomContextBatch': [
              {
                '__typename': 'v2_InboxRoomContextRow',
                'beaconId': _beaconId,
                'postRootExcerpt': 'Who is in for a ride?',
                'isRoomMember': false,
                'roomUnreadCount': 0,
              },
            ],
          },
        },
        <WireSent>[],
        (remote) async {
          final repo = InboxRepository(
            remote,
            BeaconRoomHintsRepository(remote),
          );
          final items = await repo.fetch(userId: _userId);
          expect(items, hasLength(1));
          final item = items.single;
          expect(item.status, InboxItemStatus.rejected);
          expect(item.beacon?.kind, BeaconKind.post);
          expect(item.beacon?.isRequest, isFalse);
          expect(item.roomHints?.postRootExcerpt, 'Who is in for a ride?');
        },
      );
    },
  );
}
