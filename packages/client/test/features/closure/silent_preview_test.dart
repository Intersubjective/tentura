// A20: client-side Dart port of the silent settlement (Arch §5.5 with every
// support ignored). Vectors V1/V2/V8 copied from the server's
// `episode_settlement_test.dart` (`silent` map; pool_h = 0.7).

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';
import 'package:tentura/features/closure/domain/silent_preview.dart';

const _tol = 1e-4;
const _beaconId = 'B1';

void main() {
  const ids = ['u1', 'u2', 'u3'];

  void expectHelped(Map<String, double> got, List<double> want) {
    for (var i = 0; i < ids.length; i++) {
      expect(got[ids[i]] ?? 0, closeTo(want[i], _tol), reason: ids[i]);
    }
  }

  test('V1: equal split, everyone done', () {
    final got = silentPreview(
      beaconId: _beaconId,
      outcomes: {for (final id in ids) id: ClosureOutcome.done},
      split: null,
    );
    expectHelped(got, [0.2333, 0.2333, 0.2333]);
  });

  test('V2: split 70/20/10, everyone done', () {
    final got = silentPreview(
      beaconId: _beaconId,
      outcomes: {for (final id in ids) id: ClosureOutcome.done},
      split: {'u1': 70, 'u2': 20, 'u3': 10},
    );
    expectHelped(got, [0.3856, 0.2074, 0.1069]);
  });

  test('V8: u2 and u3 notDone, split null', () {
    final got = silentPreview(
      beaconId: _beaconId,
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
      beaconId: _beaconId,
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': ClosureOutcome.cantJudge,
        'u3': null,
      },
      split: null,
    );
    expectHelped(got, [0.2333, 0.2333, 0.2333]);
  });

  test('#489: an unanswered voluntary leaver gets no share', () {
    final got = silentPreview(
      beaconId: _beaconId,
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': ClosureOutcome.done,
        'u3': null,
      },
      split: null,
      leftVoluntarily: {'u3'},
    );
    expectHelped(got, [0.35, 0.35, 0]);
  });

  test('#489: an author outcome for a voluntary leaver still counts', () {
    final got = silentPreview(
      beaconId: _beaconId,
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': ClosureOutcome.done,
        'u3': ClosureOutcome.cantJudge,
      },
      split: null,
      leftVoluntarily: {'u3'},
    );
    expectHelped(got, [0.2333, 0.2333, 0.2333]);
  });

  test('#489: a split share of the dropped leaver goes to the rest', () {
    final got = silentPreview(
      beaconId: _beaconId,
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': ClosureOutcome.done,
        'u3': null,
      },
      split: {'u1': 40, 'u2': 40, 'u3': 20},
      leftVoluntarily: {'u3'},
    );
    expectHelped(got, [0.35, 0.35, 0]);
  });
  // PR #713 review: the preview renormalizes like the server's finalize
  // (5% rounding, 100/n for a member missing from the split).
  void expectSame(Map<String, double> got, Map<String, double> want) {
    expect(got.keys.toSet(), want.keys.toSet());
    for (final id in want.keys) {
      expect(got[id], closeTo(want[id]!, 1e-9), reason: id);
    }
  }

  test('#489: 35/35/10 plus a 20% leaver settles as 45/45/10', () {
    final got = silentPreview(
      beaconId: _beaconId,
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': ClosureOutcome.done,
        'u3': ClosureOutcome.done,
        'u4': null,
      },
      split: {'u1': 35, 'u2': 35, 'u3': 10, 'u4': 20},
      leftVoluntarily: {'u4'},
    );
    final want = silentPreview(
      beaconId: _beaconId,
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': ClosureOutcome.done,
        'u3': ClosureOutcome.done,
        'u4': ClosureOutcome.notDone,
      },
      split: {'u1': 45, 'u2': 45, 'u3': 10},
    );
    expectSame(got, want);
    expect(got['u4'], 0);
  });

  test('#489: a member missing from the split weighs 100/n, as on the '
      'server', () {
    final got = silentPreview(
      beaconId: _beaconId,
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': null,
        'u3': null,
      },
      split: {'u1': 60, 'u3': 40},
      leftVoluntarily: {'u3'},
    );
    final want = silentPreview(
      beaconId: _beaconId,
      outcomes: {
        'u1': ClosureOutcome.done,
        'u2': null,
        'u3': ClosureOutcome.notDone,
      },
      split: {'u1': 55, 'u2': 45},
    );
    expectSame(got, want);
    expect(got['u2'], greaterThan(0));
  });

  test('a split without a leaver is used as saved (guard)', () {
    final got = silentPreview(
      beaconId: _beaconId,
      outcomes: {for (final id in ids) id: ClosureOutcome.done},
      split: {'u1': 70, 'u2': 20, 'u3': 10},
      leftVoluntarily: {'u3'},
    );
    expectHelped(got, [0.3856, 0.2074, 0.1069]);
  });
}
