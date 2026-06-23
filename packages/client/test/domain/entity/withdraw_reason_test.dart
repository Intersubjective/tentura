import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/withdraw_reason.dart';

void main() {
  group('WithdrawReason.wireKey', () {
    test('maps each enum to server wire keys', () {
      expect(WithdrawReason.cannotDoIt.wireKey, 'cannot_do_it');
      expect(WithdrawReason.timing.wireKey, 'timing');
      expect(WithdrawReason.wrongFit.wireKey, 'wrong_fit');
      expect(WithdrawReason.someoneElse.wireKey, 'someone_else');
      expect(WithdrawReason.other.wireKey, 'other');
    });
  });
}
