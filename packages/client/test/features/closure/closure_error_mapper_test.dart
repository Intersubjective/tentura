import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/closure/data/model/closure_error_mapper.dart';
import 'package:tentura/features/closure/domain/closure_exception.dart';

void main() {
  // Server `ClosureExceptionCode` order; code = 1800 + index.
  final expected = <int, Matcher>{
    1800: isA<ClosureNotAuthorException>(),
    1801: isA<ClosureNotVoterException>(),
    1802: isA<ClosureNotMemberException>(),
    1803: isA<ClosureStaleEpochException>(),
    1804: isA<ClosureWrongStatusException>(),
    1805: isA<ClosureReopenLimitException>(),
    1806: isA<ClosureExtendLimitException>(),
    1807: isA<ClosureNotReadyException>(),
    1808: isA<ClosureInvalidSplitException>(),
    1809: isA<ClosureSplitTooLargeException>(),
  };

  for (final e in expected.entries) {
    test('throwIfClosureError(${e.key}) throws exactly its own type', () {
      expect(() => throwIfClosureError(e.key), throwsA(e.value));
      // And no other code's type.
      for (final other in expected.entries.where((o) => o.key != e.key)) {
        expect(
          () => throwIfClosureError(e.key),
          isNot(throwsA(other.value)),
          reason: '${e.key} must not map to the ${other.key} exception',
        );
      }
    });
  }

  test('every closure exception is a ClosureException with en/ru text', () {
    final all = <ClosureException>[
      const ClosureNotAuthorException(),
      const ClosureNotVoterException(),
      const ClosureNotMemberException(),
      const ClosureStaleEpochException(),
      const ClosureWrongStatusException(),
      const ClosureReopenLimitException(),
      const ClosureExtendLimitException(),
      const ClosureNotReadyException(),
      const ClosureInvalidSplitException(),
      const ClosureSplitTooLargeException(),
    ];
    expect(all.map((e) => e.toEn).toSet(), hasLength(10));
    expect(all.map((e) => e.toRu).toSet(), hasLength(10));
  });

  test('throwIfClosureError ignores foreign and null codes', () {
    expect(() => throwIfClosureError(null), returnsNormally);
    expect(() => throwIfClosureError(1401), returnsNormally);
    expect(() => throwIfClosureError(1799), returnsNormally);
    expect(() => throwIfClosureError(1810), returnsNormally);
    for (final code in [...List.generate(100, (i) => 1700 + i), 1810, 1900]) {
      expect(() => throwIfClosureError(code), returnsNormally, reason: '$code');
    }
  });
}
