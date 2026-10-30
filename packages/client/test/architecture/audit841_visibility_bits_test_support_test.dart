@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'W9: BeaconActivityEventVisibilityBits lives in test support, not lib',
    () {
      final libSource = File(
        'lib/domain/entity/beacon_activity_event_consts.dart',
      ).readAsStringSync();
      expect(
        libSource.contains('BeaconActivityEventVisibilityBits'),
        isFalse,
      );
      expect(
        File('test/support/beacon_activity_event_visibility_bits.dart')
            .existsSync(),
        isTrue,
      );
    },
  );
}
