// #364 / #489: a request in its (second) final check after one Reopen where
// the only helper(s) were removed by the author. Product decision (§P3, kept):
// an early close needs an explicit outcome for every member, removed ones
// included; once the author has picked them, "Finish now" is available at
// once (no 48 h grace: nobody is left who could answer the review). Pure rule:
// `ClosureCase.canCloseNow`, used by both `closureState` and `closeNow`.
//
// Guards: an unjudged member still blocks; a voluntary leaver keeps the vote
// (U49); a removal does not skip waiting on helpers who are still there.

import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';

/// Round 2 (after the one Reopen) opened at this moment.
final _opened = DateTime.utc(2026, 10, 21, 4, 17);

/// One minute into the round: far inside the 48 h grace.
final _now = _opened.add(const Duration(minutes: 1));

ClosureEpoch _round2() => ClosureEpoch(
  beaconId: 'B1',
  epoch: 2,
  status: ClosureEpochStatus.evaluating,
  openedAt: _opened,
  closesAt: _opened.add(const Duration(days: 7)),
  extensionsUsed: 0,
);

/// Active when the round opened, removed by the author during it.
ClosureMemberRow _removedDuring(String id) => ClosureMemberRow(
  userId: id,
  activeAtOpen: true,
  departure: Departure.removed,
);

/// Removed after the Reopen, before the second final check opened.
ClosureMemberRow _removedBefore(String id) => ClosureMemberRow(
  userId: id,
  activeAtOpen: false,
  departure: Departure.removed,
);

ClosureMemberRow _active(String id) =>
    ClosureMemberRow(userId: id, activeAtOpen: true);

ClosureMemberRow _leftVoluntarily(String id) => ClosureMemberRow(
  userId: id,
  activeAtOpen: true,
  departure: Departure.voluntary,
);

List<ClosureOutcomeRow> _done(List<String> ids) => [
  for (final id in ids)
    ClosureOutcomeRow(
      helperId: id,
      outcome: ClosureOutcome.done,
      updatedAt: _opened,
    ),
];

bool _canCloseNow(
  List<ClosureMemberRow> members, {
  List<ClosureOutcomeRow> outcomes = const [],
  List<ClosureCommitRow> commits = const [],
}) => ClosureCase.canCloseNow(
  epoch: _round2(),
  members: members,
  outcomes: outcomes,
  commits: commits,
  now: _now,
);

void main() {
  group('Finish now once every removed helper has an outcome', () {
    test('the only helper was removed and judged: at once', () {
      final members = [_removedDuring('h1')];
      expect(members.where(ClosureCase.isVoter), isEmpty);
      expect(_canCloseNow(members), isFalse);
      expect(_canCloseNow(members, outcomes: _done(['h1'])), isTrue);
    });

    test('the only helper was removed before the second final check', () {
      final members = [_removedBefore('h1')];
      expect(_canCloseNow(members, outcomes: _done(['h1'])), isTrue);
    });

    test('three helpers, all removed and judged: no 48 h wait', () {
      final members = [
        _removedDuring('h1'),
        _removedBefore('h2'),
        _removedDuring('h3'),
      ];
      expect(members.where(ClosureCase.isVoter), isEmpty);
      expect(_canCloseNow(members, outcomes: _done(['h2'])), isFalse);
      expect(
        _canCloseNow(members, outcomes: _done(['h1', 'h2', 'h3'])),
        isTrue,
      );
    });
  });

  group('kept as is', () {
    test('an active helper without an outcome still blocks Finish now', () {
      expect(_canCloseNow([_active('h1')]), isFalse);
      expect(_canCloseNow([_active('h1'), _removedDuring('h2')]), isFalse);
      expect(_canCloseNow([_active('h1')], outcomes: _done(['h1'])), isTrue);
    });

    test('a voluntary leaver keeps the vote and still needs an outcome', () {
      final members = [_leftVoluntarily('h1')];
      expect(members.where(ClosureCase.isVoter), hasLength(1));
      expect(_canCloseNow(members), isFalse);
      expect(_canCloseNow(members, outcomes: _done(['h1'])), isTrue);
    });

    test('removals do not skip waiting on a voter who is still there', () {
      final members = [
        _removedDuring('h1'),
        _removedBefore('h2'),
        _active('h3'),
      ];
      // h3 judged but has not answered the review; < 48 h.
      expect(_canCloseNow(members, outcomes: _done(['h3'])), isFalse);
      expect(
        _canCloseNow(members, outcomes: _done(['h1', 'h2', 'h3'])),
        isFalse,
      );
      expect(
        _canCloseNow(
          members,
          outcomes: _done(['h1', 'h2', 'h3']),
          commits: [ClosureCommitRow(voterId: 'h3', committedAt: _now)],
        ),
        isTrue,
      );
    });
  });
}
