import 'package:flutter_test/flutter_test.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_status_change.dart';

RoomMessage _line(String? payload, {int? kind}) => RoomMessage(
  id: 'R1',
  beaconId: 'B1',
  authorId: '',
  body: '',
  createdAt: DateTime.utc(2026, 10, 16),
  systemMessageKind: kind ?? BeaconRoomSystemMessageKind.statusChanged,
  systemPayloadJson: payload,
);

void main() {
  test('reads from, to and reason', () {
    final change = RoomStatusChange.fromMessage(
      _line(
        '{"version":1,"fromStatus":5,"toStatus":6,'
        '"reason":"closureExpired"}',
      ),
    )!;
    expect(change.from, BeaconStatus.fromSmallint(5));
    expect(change.to, BeaconStatus.fromSmallint(6));
    expect(change.isAutomatic, isTrue);
  });

  test('a person-made reason is not automatic', () {
    final change = RoomStatusChange.fromMessage(
      _line(
        '{"version":1,"fromStatus":1,"toStatus":3,"reason":"enoughHelp"}',
      ),
    )!;
    expect(change.isAutomatic, isFalse);
  });

  test('null for other rows and unreadable payloads', () {
    expect(RoomStatusChange.fromMessage(_line(null)), isNull);
    expect(RoomStatusChange.fromMessage(_line('not json')), isNull);
    expect(
      RoomStatusChange.fromMessage(
        _line('{"version":2,"fromStatus":1,"toStatus":3}'),
      ),
      isNull,
    );
    expect(
      RoomStatusChange.fromMessage(
        _line(
          '{"version":1,"fromStatus":1,"toStatus":3}',
          kind: BeaconRoomSystemMessageKind.statusChanged + 1,
        ),
      ),
      isNull,
    );
  });
}
