import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_tile.dart';

import '../../support/baton_together_projection_accessors.dart';

void main() {
  group('marker-12 baton taken payload', () {
    test('exposes coTakerUserId alongside takerUserId', () {
      final message = RoomMessage(
        id: 'M1',
        beaconId: 'B1',
        authorId: 'Uauthor',
        body: '',
        createdAt: DateTime.utc(2026, 10, 5),
        systemPayloadJson: jsonEncode({
          'batonId': 'Lbaton1',
          'sourceMessageId': 'Msource',
          'takerUserId': 'Uaaaaaaaaaaa',
          'coTakerUserId': 'Uyyyyyyyyyyy',
        }),
      );

      expect(RoomMessageTile.batonTakerUserId(message), 'Uaaaaaaaaaaa');
      expect(batonCoTakerUserId(message), 'Uyyyyyyyyyyy');
    });
  });
}
