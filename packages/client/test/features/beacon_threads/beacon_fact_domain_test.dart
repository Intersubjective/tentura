import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/domain/entity/beacon_fact_card_consts.dart';
import 'package:tentura/domain/entity/quoted_fact.dart';
import 'package:tentura/features/beacon_threads/domain/exception/beacon_fact_card_exceptions.dart';

QuotedFact _quote({
  required int seq,
  required int currentSeq,
  int status = BeaconFactCardStatusBits.active,
}) => QuotedFact(
  factCardId: 'F1',
  seq: seq,
  currentSeq: currentSeq,
  status: status,
  factText: 'text',
);

void main() {
  group('QuotedFact', () {
    test('isChangedSinceQuoted is true when currentSeq > seq', () {
      expect(_quote(seq: 2, currentSeq: 3).isChangedSinceQuoted, isTrue);
    });

    test('isChangedSinceQuoted is false when seqs are equal', () {
      expect(_quote(seq: 3, currentSeq: 3).isChangedSinceQuoted, isFalse);
    });

    test('isUnpinned is true when status is removed', () {
      final q = _quote(
        seq: 1,
        currentSeq: 1,
        status: BeaconFactCardStatusBits.removed,
      );
      expect(q.isUnpinned, isTrue);
      expect(_quote(seq: 1, currentSeq: 1).isUnpinned, isFalse);
    });
  });

  group('throwIfBeaconFactCardError', () {
    test('1318 -> BeaconFactEditConflictException with currentSeq', () {
      expect(
        () => throwIfBeaconFactCardError(1318, {'currentSeq': 4}),
        throwsA(
          isA<BeaconFactEditConflictException>().having(
            (e) => (e as BeaconFactEditConflictException).currentSeq,
            'currentSeq',
            4,
          ),
        ),
      );
    });

    test('1319 -> BeaconFactRemovedException', () {
      expect(
        () => throwIfBeaconFactCardError(1319, null),
        throwsA(isA<BeaconFactRemovedException>()),
      );
    });

    test('1320 -> BeaconFactRateLimitedException', () {
      expect(
        () => throwIfBeaconFactCardError(1320, null),
        throwsA(isA<BeaconFactRateLimitedException>()),
      );
    });

    test('1317 does not throw', () {
      expect(() => throwIfBeaconFactCardError(1317, null), returnsNormally);
    });
  });
}
