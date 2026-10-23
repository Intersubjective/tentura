import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_room_consts.dart';

void main() {
  test('clipBeaconRoomCurrentLine leaves short text unchanged', () {
    expect(
      clipBeaconRoomCurrentLine('Coordinate pickup at noon'),
      'Coordinate pickup at noon',
    );
  });

  test('clipBeaconRoomCurrentLine leaves text at max length unchanged', () {
    final exact = 'a' * kBeaconRoomCurrentLineMaxLength;
    expect(clipBeaconRoomCurrentLine(exact), exact);
  });

  test('clipBeaconRoomCurrentLine truncates at max length with ellipsis', () {
    final long = 'a' * (kBeaconRoomCurrentLineMaxLength + 10);
    final clipped = clipBeaconRoomCurrentLine(long);
    expect(clipped.length, kBeaconRoomCurrentLineMaxLength);
    expect(clipped.endsWith('…'), isTrue);
    expect(
      clipped.startsWith('a' * (kBeaconRoomCurrentLineMaxLength - 1)),
      isTrue,
    );
  });

  // #603: the cut fell between the two halves of an emoji, leaving a lone
  // surrogate (an invalid string that renders as a box or breaks encoding).
  test('clipBeaconRoomCurrentLine never splits an emoji at the cut', () {
    const max = kBeaconRoomCurrentLineMaxLength;
    // The emoji takes code units max-2 and max-1: the old cut kept only its
    // first half.
    final long = '${'a' * (max - 2)}😀 and more text';
    final clipped = clipBeaconRoomCurrentLine(long);
    expect(clipped, '${'a' * (max - 2)}…');
    expect(clipped.length, lessThanOrEqualTo(max));
    for (final unit in clipped.codeUnits) {
      expect(unit >= 0xD800 && unit <= 0xDFFF, isFalse);
    }
  });

  test('clipBeaconRoomCurrentLine keeps an emoji that fits whole', () {
    const max = kBeaconRoomCurrentLineMaxLength;
    final long = '${'a' * (max - 3)}😀 and more text';
    final clipped = clipBeaconRoomCurrentLine(long);
    expect(clipped, '${'a' * (max - 3)}😀…');
    expect(clipped.length, max);
  });
}
