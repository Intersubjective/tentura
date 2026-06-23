import 'package:test/test.dart';

import 'package:tentura_server/domain/coordination/withdraw_reason.dart';

void main() {
  group('isAllowedWithdrawReason', () {
    test('accepts known reason keys', () {
      for (final reason in kAllowedWithdrawReasonKeys) {
        expect(isAllowedWithdrawReason(reason), isTrue);
      }
    });

    test('rejects null, empty, and unknown reasons', () {
      expect(isAllowedWithdrawReason(null), isFalse);
      expect(isAllowedWithdrawReason(''), isFalse);
      expect(isAllowedWithdrawReason('not_a_reason'), isFalse);
    });
  });
}
