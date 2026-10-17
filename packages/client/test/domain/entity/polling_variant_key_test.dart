import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/polling.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';

void main() {
  group('Polling.variantKey', () {
    test('equal after trim, inner whitespace and case, like the server', () {
      expect(Polling.variantKey('  Next   Monday '), 'next monday');
      expect(
        Polling.variantKey('Next Monday'),
        Polling.variantKey('next  MONDAY'),
      );
    });

    test('different words stay different', () {
      expect(
        Polling.variantKey('Monday'),
        isNot(Polling.variantKey('Tuesday')),
      );
    });
  });

  test('a whitespace-only option is too short, not a duplicate', () {
    expect(
      () => Polling.variantValidator('  '),
      throwsA(isA<PollingVariantTooShortException>()),
    );
  });
}
