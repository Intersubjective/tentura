import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// tentura-igu (tentura-617.31): `fact_history_cubit_test.dart` still carries a
/// TDD header claiming `FactHistoryCubit` is missing even though the cubit
/// ships and the test file imports it — that stale copy misleads readers and
/// must be removed once the implementation exists.
void main() {
  const cubitPath =
      'lib/features/beacon_threads/ui/bloc/fact_history_cubit.dart';
  const statePath =
      'lib/features/beacon_threads/ui/bloc/fact_history_state.dart';
  const testPath = 'test/features/beacon_threads/fact_history_cubit_test.dart';

  test(
    'fact_history_cubit_test header does not claim FactHistoryCubit is missing',
    () {
      expect(File(cubitPath).existsSync(), isTrue, reason: cubitPath);
      expect(File(statePath).existsSync(), isTrue, reason: statePath);

      final testSource = File(testPath).readAsStringSync();
      expect(
        testSource,
        contains(
          "import 'package:tentura/features/beacon_threads/ui/bloc/fact_history_cubit.dart';",
        ),
        reason: 'cubit tests must import the real cubit',
      );

      final headerEnd = testSource.indexOf('\n\nimport ');
      expect(headerEnd, greaterThan(0), reason: 'expected header before imports');
      final header = testSource.substring(0, headerEnd);

      expect(
        header,
        isNot(contains('`FactHistoryCubit` does not exist yet')),
        reason:
            'remove the stale TDD claim once FactHistoryCubit is implemented',
      );
      expect(
        header,
        isNot(contains('this file does not compile')),
        reason: 'fact_history_cubit_test.dart compiles with FactHistoryCubit',
      );
      expect(
        header,
        isNot(
          contains(
            'every test below fails until it (and `FactHistoryState`) are added',
          ),
        ),
        reason:
            'FactHistoryState and FactHistoryCubit exist; header must describe '
            'current behavior instead of a pre-implementation placeholder',
      );
    },
  );
}
