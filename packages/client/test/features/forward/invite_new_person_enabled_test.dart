import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/forward/domain/invite_new_person_enabled.dart';

void main() {
  test('invite is off without a request id', () {
    expect(
      inviteNewPersonEnabled(beaconId: '', allowsForward: true, isLive: true),
      isFalse,
    );
  });

  test('invite is off on a draft that is not live', () {
    expect(inviteNewPersonEnabled(beaconId: 'B1'), isFalse);
  });

  test('invite is on when the request allows forwarding', () {
    expect(
      inviteNewPersonEnabled(beaconId: 'B1', allowsForward: true),
      isTrue,
    );
  });

  test('invite is on when the create session is live', () {
    expect(
      inviteNewPersonEnabled(beaconId: 'B1', isLive: true),
      isTrue,
    );
  });
}
