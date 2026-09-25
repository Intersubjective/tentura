import 'package:test/test.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/exception_codes.dart';

/// Issue #181 — fact-history error codes. The client hard-codes 1318–1320
/// (`beacon_fact_card_exceptions.dart`), so the enum values must be appended
/// after [BeaconExceptionCode.beaconHierarchyCursorInvalid] without
/// renumbering anything.
void main() {
  group('BeaconExceptionCode fact codes', () {
    test('beaconHierarchyCursorInvalid is still 1317', () {
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.beaconHierarchyCursorInvalid,
        ).codeNumber,
        1317,
      );
    });

    test('new fact codes serialise to 1318, 1319, 1320', () {
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.beaconFactCardEditConflict,
        ).codeNumber,
        1318,
      );
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.beaconFactCardRemoved,
        ).codeNumber,
        1319,
      );
      expect(
        const BeaconExceptionCodes(
          BeaconExceptionCode.beaconFactCardRateLimited,
        ).codeNumber,
        1320,
      );
    });

    test('fact codes are the last enum values', () {
      expect(
        BeaconExceptionCode.values.last,
        BeaconExceptionCode.beaconFactCardRateLimited,
      );
    });
  });

  group('fact card exceptions', () {
    test('EditConflict carries code 1318 and currentSeq in extensions', () {
      const e = BeaconFactCardEditConflictException(currentSeq: 7);
      expect(e.code.codeNumber, 1318);
      expect(e.currentSeq, 7);
      final extensions = e.toMap['extensions']! as Map<String, Object>;
      expect(extensions['code'], '1318');
      expect(extensions['currentSeq'], 7);
    });

    test('EditConflict exposes extensions with currentSeq (AC accessor)', () {
      const e = BeaconFactCardEditConflictException(currentSeq: 7);
      expect(e.extensions['currentSeq'], 7);
      expect(e.extensions['code'], '1318');
      expect(e.extensions, e.toMap['extensions']);
    });

    test('Removed carries code 1319', () {
      const e = BeaconFactCardRemovedException();
      expect(e.code.codeNumber, 1319);
      final extensions = e.toMap['extensions']! as Map<String, Object>;
      expect(extensions['code'], '1319');
    });

    test('RateLimited carries code 1320', () {
      const e = BeaconFactCardRateLimitedException();
      expect(e.code.codeNumber, 1320);
      final extensions = e.toMap['extensions']! as Map<String, Object>;
      expect(extensions['code'], '1320');
    });

    test('exceptions are ExceptionBase so GraphQL serialises them', () {
      expect(
        const BeaconFactCardEditConflictException(currentSeq: 1),
        isA<ExceptionBase>(),
      );
      expect(const BeaconFactCardRemovedException(), isA<ExceptionBase>());
      expect(const BeaconFactCardRateLimitedException(), isA<ExceptionBase>());
    });
  });
}
