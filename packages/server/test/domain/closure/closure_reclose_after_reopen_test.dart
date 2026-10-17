// B041: after the one allowed Reopen, the Request goes through "Wrapping up"
// again and closes through the normal review. These are the rules the second
// round runs on (`ClosureCase.canCloseNow` / `canReopen`, both pure); the
// write path is covered by closure_case_lifecycle_test (pg).

import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';

final _round1Opened = DateTime.utc(2026, 10, 1, 9);

/// Round 2 opened three days after round 1 (the Reopen cancelled round 1).
final _round2Opened = DateTime.utc(2026, 10, 4, 9);

ClosureEpoch _round2() => ClosureEpoch(
  beaconId: 'B1',
  epoch: 2,
  status: ClosureEpochStatus.evaluating,
  openedAt: _round2Opened,
  closesAt: _round2Opened.add(const Duration(days: 7)),
  extensionsUsed: 0,
);

List<ClosureMemberRow> _members(List<String> ids) => [
  for (final id in ids) ClosureMemberRow(userId: id, activeAtOpen: true),
];

/// Outcomes are kept across a Reopen (only committed supports are cleared).
List<ClosureOutcomeRow> _outcomes(List<String> ids) => [
  for (final id in ids)
    ClosureOutcomeRow(
      helperId: id,
      outcome: ClosureOutcome.done,
      updatedAt: _round1Opened.add(const Duration(hours: 1)),
    ),
];

void main() {
  group('second wrap-up round after a Reopen', () {
    test('a second Reopen is not offered (one per Request)', () {
      expect(
        ClosureCase.canReopen(live: _round2(), cancelledEpochs: 1),
        isFalse,
      );
      expect(
        ClosureCase.canReopen(live: _round2(), cancelledEpochs: 0),
        isTrue,
      );
    });

    test('two helpers, outcomes kept from round 1: Close now right away', () {
      expect(
        ClosureCase.canCloseNow(
          epoch: _round2(),
          members: _members(['h1', 'h2']),
          outcomes: _outcomes(['h1', 'h2']),
          commits: const [],
          now: _round2Opened.add(const Duration(minutes: 1)),
        ),
        isTrue,
      );
    });

    test('a helper who joined after the Reopen still needs an outcome', () {
      final now = _round2Opened.add(const Duration(minutes: 1));
      final members = _members(['h1', 'h2']);
      expect(
        ClosureCase.canCloseNow(
          epoch: _round2(),
          members: members,
          outcomes: _outcomes(['h1']),
          commits: const [],
          now: now,
        ),
        isFalse,
      );
      expect(
        ClosureCase.canCloseNow(
          epoch: _round2(),
          members: members,
          outcomes: _outcomes(['h1', 'h2']),
          commits: const [],
          now: now,
        ),
        isTrue,
      );
    });

    group('three helpers', () {
      final members = _members(['h1', 'h2', 'h3']);
      final outcomes = _outcomes(['h1', 'h2', 'h3']);

      test('the 48 h grace counts from round 2, not round 1', () {
        // 75 h after round 1 opened, 1 h into round 2.
        expect(
          ClosureCase.canCloseNow(
            epoch: _round2(),
            members: members,
            outcomes: outcomes,
            commits: const [],
            now: _round2Opened.add(const Duration(hours: 1)),
          ),
          isFalse,
        );
        expect(
          ClosureCase.canCloseNow(
            epoch: _round2(),
            members: members,
            outcomes: outcomes,
            commits: const [],
            now: _round2Opened.add(const Duration(hours: 48)),
          ),
          isTrue,
        );
      });

      test('or as soon as every voter answers in round 2', () {
        final at = _round2Opened.add(const Duration(hours: 2));
        expect(
          ClosureCase.canCloseNow(
            epoch: _round2(),
            members: members,
            outcomes: outcomes,
            commits: [
              for (final id in ['h1', 'h2', 'h3'])
                ClosureCommitRow(voterId: id, committedAt: at),
            ],
            now: at,
          ),
          isTrue,
        );
      });
    });
  });
}
