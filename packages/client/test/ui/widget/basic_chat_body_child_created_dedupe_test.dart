import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/ui/widget/basic_chat_body.dart';

RoomMessage _msg({
  required String id,
  int? systemMessageKind,
  Map<String, Object?>? payload,
}) => RoomMessage(
  id: id,
  beaconId: 'b1',
  authorId: 'u1',
  author: const Profile(id: 'u1', displayName: 'Author'),
  body: '',
  createdAt: DateTime.utc(2026, 1, 1),
  systemMessageKind: systemMessageKind,
  systemPayloadJson: payload == null ? null : jsonEncode(payload),
);

void main() {
  group('isRedundantChildCreatedNotice', () {
    test('true when source message is in the loaded page', () {
      final notice = _msg(
        id: 'notice-1',
        systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
        payload: {
          'version': 1,
          'kind': 'childCreated',
          'childBeaconId': 'child-1',
          'sourceMessageId': 'source-1',
        },
      );
      expect(
        isRedundantChildCreatedNotice(notice, {'source-1', 'notice-1'}),
        isTrue,
      );
    });

    test('false when source is missing from this page (pagination)', () {
      final notice = _msg(
        id: 'notice-1',
        systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
        payload: {
          'version': 1,
          'kind': 'childCreated',
          'childBeaconId': 'child-1',
          'sourceMessageId': 'source-missing',
        },
      );
      expect(
        isRedundantChildCreatedNotice(notice, {'notice-1'}),
        isFalse,
      );
    });

    test('false for standalone create without sourceMessageId', () {
      final notice = _msg(
        id: 'notice-1',
        systemMessageKind: BeaconRoomSystemMessageKind.childCreated,
        payload: {
          'version': 1,
          'kind': 'childCreated',
          'childBeaconId': 'child-1',
        },
      );
      expect(
        isRedundantChildCreatedNotice(notice, {'notice-1'}),
        isFalse,
      );
    });

    test('false for ordinary messages', () {
      expect(
        isRedundantChildCreatedNotice(_msg(id: 'm1'), {'m1'}),
        isFalse,
      );
    });
  });
}
