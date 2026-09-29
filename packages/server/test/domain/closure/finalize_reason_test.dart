import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/finalize_reason.dart';

void main() {
  group('FinalizeReason', () {
    test('maps beacon_closure.finalize_reason CHECK values 1 and 2', () {
      expect(FinalizeReason.authorCloseNow.dbValue, 1);
      expect(FinalizeReason.expired.dbValue, 2);
    });

    test('tryFromInt round-trips known values', () {
      expect(
        FinalizeReason.tryFromInt(1),
        FinalizeReason.authorCloseNow,
      );
      expect(FinalizeReason.tryFromInt(2), FinalizeReason.expired);
      expect(FinalizeReason.tryFromInt(0), isNull);
      expect(FinalizeReason.tryFromInt(3), isNull);
      expect(FinalizeReason.tryFromInt(null), isNull);
    });
  });
}
