// PR #713 review (#489): the client port of the server's set-A rule and
// split arithmetic. Vectors copied from the server's `author_split_test.dart`
// (same beacon id, so the sha256 tie-break must match too).

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/closure/domain/closure_split.dart';
import 'package:tentura/features/closure/domain/entity/closure_outcome.dart';

const _beaconId = 'B1';

void main() {
  group('renormalizeSplit / apportionSplit (server vectors)', () {
    test('E1 renormalize adds member u4', () {
      expect(
        renormalizeSplit(
          current: {'u1': 70, 'u2': 20, 'u3': 10},
          newA: {'u1', 'u2', 'u3', 'u4'},
          beaconId: _beaconId,
        ),
        {'u1': 55, 'u2': 15, 'u3': 10, 'u4': 20},
      );
    });

    test('E2 apportion water-fill with skewed weights', () {
      expect(
        apportionSplit(
          total: 100,
          weights: {'u1': 90, 'u2': 4, 'u3': 3, 'u4': 3},
          min: 5,
          beaconId: _beaconId,
        ),
        {'u1': 85, 'u2': 5, 'u3': 5, 'u4': 5},
      );
    });

    test('E4 tie-break: equal remainders go by sha256 like the server', () {
      // The rest of the server's moveSlider(u1 -> 45) over three equals.
      expect(
        apportionSplit(
          total: 55,
          weights: {'u2': 1, 'u3': 1},
          min: 5,
          beaconId: _beaconId,
        ),
        {'u2': 30, 'u3': 25},
      );
      expect(
        apportionSplit(
          total: 55,
          weights: {'u3': 1, 'u2': 1},
          min: 5,
          beaconId: _beaconId,
        ),
        {'u2': 30, 'u3': 25},
        reason: 'map order does not matter',
      );
      // sha256('B1:u4') < sha256('B1:u3') (checked with Python hashlib):
      // the hash, not the id order, picks who gets the extra 5.
      expect(
        apportionSplit(
          total: 55,
          weights: {'u3': 1, 'u4': 1},
          min: 5,
          beaconId: _beaconId,
        ),
        {'u3': 25, 'u4': 30},
      );
    });

    test('E7 renormalize shrinks A to two members', () {
      expect(
        renormalizeSplit(
          current: {'u1': 70, 'u2': 20, 'u3': 10},
          newA: {'u1', 'u2'},
          beaconId: _beaconId,
        ),
        {'u1': 80, 'u2': 20},
      );
    });

    test('E8 renormalize singleton A', () {
      expect(
        renormalizeSplit(
          current: {'u1': 70, 'u2': 20, 'u3': 10},
          newA: {'u1'},
          beaconId: _beaconId,
        ),
        {'u1': 100},
      );
    });

    test('E10/E11 renormalize past 20 or to nobody returns null', () {
      expect(
        renormalizeSplit(
          current: {for (var i = 1; i <= 20; i++) 'h$i': 5},
          newA: {for (var i = 1; i <= 21; i++) 'h$i'},
          beaconId: _beaconId,
        ),
        isNull,
      );
      expect(
        renormalizeSplit(
          current: {'u1': 50, 'u2': 50},
          newA: {},
          beaconId: _beaconId,
        ),
        isNull,
      );
    });

    test('review example: 35/35/10 without the 20% leaver is 45/45/10', () {
      expect(
        renormalizeSplit(
          current: {'u1': 35, 'u2': 35, 'u3': 10, 'u4': 20},
          newA: {'u1', 'u2', 'u3'},
          beaconId: _beaconId,
        ),
        {'u1': 45, 'u2': 45, 'u3': 10},
      );
    });
  });

  group('closureSetA (#489)', () {
    const ids = ['u1', 'u2', 'u3', 'u4'];

    test('drops notDone and an unjudged voluntary leaver only', () {
      expect(
        closureSetA(
          ids: ids,
          outcomes: {
            'u1': ClosureOutcome.done,
            'u2': ClosureOutcome.notDone,
            'u3': null,
            'u4': null,
          },
          leftVoluntarily: {'u4'},
        ),
        ['u1', 'u3'],
      );
    });

    test('an outcome from the author brings the leaver back', () {
      expect(
        closureSetA(
          ids: ids,
          outcomes: {
            'u1': ClosureOutcome.done,
            'u2': ClosureOutcome.done,
            'u3': ClosureOutcome.done,
            'u4': ClosureOutcome.cantJudge,
          },
          leftVoluntarily: {'u4'},
        ),
        ids,
      );
    });
  });

  group('closureSettledSplit', () {
    test('keeps a saved split that gives no leaver a share', () {
      final split = {'u1': 70, 'u2': 30};
      expect(
        closureSettledSplit(
          split: split,
          outcomes: {
            'u1': ClosureOutcome.done,
            'u2': ClosureOutcome.done,
            'u3': null,
          },
          leftVoluntarily: {'u3'},
          beaconId: _beaconId,
        ),
        split,
      );
    });

    test('every member left unjudged: equal (null), like the server', () {
      expect(
        closureSettledSplit(
          split: {'u1': 50, 'u2': 50},
          outcomes: {'u1': null, 'u2': null},
          leftVoluntarily: {'u1', 'u2'},
          beaconId: _beaconId,
        ),
        isNull,
      );
    });
  });
}
