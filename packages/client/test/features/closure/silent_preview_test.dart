// A20: client-side Dart port of the silent settlement (Arch §5.5 with every
// support ignored). Vectors V1/V2/V8 copied from the server's
// `episode_settlement_test.dart` (`silent` map; pool_h = 0.7).

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/silent_preview.dart';

const _tol = 1e-4;

void main() {
  const ids = ['u1', 'u2', 'u3'];

  void expectHelped(Map<String, double> got, List<double> want) {
    for (var i = 0; i < ids.length; i++) {
      expect(got[ids[i]] ?? 0, closeTo(want[i], _tol), reason: ids[i]);
    }
  }

  test('V1: equal split, everyone done', () {
    final got = silentPreview(
      outcomes: {for (final id in ids) id: ClosureOutcome.done},
      split: null,
    );
    expectHelped(got, [0.2333, 0.2333, 0.2333]);
  });

  test('V2: split 70/20/10, everyone done', () {
    final got = silentPreview(
      outcomes: {for (final id in ids) id: ClosureOutcome.done},
      split: {'u1': 70, 'u2': 20, 'u3': 10},
    );
    expectHelped(got, [0.3856, 0.2074, 0.1069]);
  });

  test('V8: u2 and u3 notDone, split null', () {
    final got = silentPreview(
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': ClosureOutcome.notDone,
        'u3': ClosureOutcome.notDone,
      },
      split: null,
    );
    expectHelped(got, [0.4667, 0, 0]);
  });

  test('V7: cantJudge and unanswered stay in an equal share', () {
    final got = silentPreview(
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': ClosureOutcome.cantJudge,
        'u3': null,
      },
      split: null,
    );
    expectHelped(got, [0.2333, 0.2333, 0.2333]);
  });
}
