import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';

void main() {
  test('clipBeaconRoomCurrentLine leaves short text unchanged', () {
    expect(
      clipBeaconRoomCurrentLine('Coordinate pickup at noon'),
      'Coordinate pickup at noon',
    );
  });

  test('clipBeaconRoomCurrentLine truncates at max length with ellipsis', () {
    final long = 'a' * (kBeaconRoomCurrentLineMaxLength + 10);
    final clipped = clipBeaconRoomCurrentLine(long);
    expect(clipped.length, kBeaconRoomCurrentLineMaxLength);
    expect(clipped.endsWith('…'), isTrue);
    expect(clipped.startsWith('a' * (kBeaconRoomCurrentLineMaxLength - 1)), isTrue);
  });
}
