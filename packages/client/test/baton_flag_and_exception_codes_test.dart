import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/features/beacon_threads/domain/exception/baton_exceptions.dart';

void main() {
  test('baton start action is enabled for release', () {
    expect(kBatonEnabled, isTrue);
  });

  group('baton exception codes mirror the server', () {
    test('code numbers', () {
      expect(BatonNotFoundException.codeNumber, 1322);
      expect(BatonNotAuthorException.codeNumber, 1323);
      expect(BatonNotCandidateException.codeNumber, 1324);
      expect(BatonNotCollectingException.codeNumber, 1325);
      expect(BatonInvalidCandidatesException.codeNumber, 1326);
      expect(BatonAlreadyActiveException.codeNumber, 1327);
      expect(BatonTakerNotAvailableException.codeNumber, 1328);
      expect(BatonMessageNotEligibleException.codeNumber, 1329);
    });

    test('throwIfBatonError throws the matching typed exception', () {
      expect(
        () => throwIfBatonError(1322),
        throwsA(isA<BatonNotFoundException>()),
      );
      expect(
        () => throwIfBatonError(1323),
        throwsA(isA<BatonNotAuthorException>()),
      );
      expect(
        () => throwIfBatonError(1324),
        throwsA(isA<BatonNotCandidateException>()),
      );
      expect(
        () => throwIfBatonError(1325),
        throwsA(isA<BatonNotCollectingException>()),
      );
      expect(
        () => throwIfBatonError(1326),
        throwsA(isA<BatonInvalidCandidatesException>()),
      );
      expect(
        () => throwIfBatonError(1327),
        throwsA(isA<BatonAlreadyActiveException>()),
      );
      expect(
        () => throwIfBatonError(1328),
        throwsA(isA<BatonTakerNotAvailableException>()),
      );
      expect(
        () => throwIfBatonError(1329),
        throwsA(isA<BatonMessageNotEligibleException>()),
      );
    });

    test('throwIfBatonError ignores unrelated codes', () {
      expect(() => throwIfBatonError(1320), returnsNormally);
      expect(() => throwIfBatonError(1330), returnsNormally);
      expect(() => throwIfBatonError(null), returnsNormally);
    });
  });
}
