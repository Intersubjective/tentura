// #632 (#364): the server, not the client, decides when the early-close date
// matters. `ClosureCase.earlyCloseAt` is what `closureState` sends as
// `earlyCloseAt`: the end of the 48 h review grace, or null when the grace
// cannot matter (a small episode closes without the review; with no voter
// left nobody can answer it). The client shows its hint only for a non-null
// value, so it no longer copies the server's small-episode size.

import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';

final _opened = DateTime.utc(2026, 10, 21, 4, 17);

ClosureEpoch _epoch() => ClosureEpoch(
  beaconId: 'B1',
  epoch: 1,
  status: ClosureEpochStatus.evaluating,
  openedAt: _opened,
  closesAt: _opened.add(const Duration(days: 7)),
  extensionsUsed: 0,
);

ClosureMemberRow _active(String id) =>
    ClosureMemberRow(userId: id, activeAtOpen: true);

ClosureMemberRow _removed(String id) => ClosureMemberRow(
  userId: id,
  activeAtOpen: true,
  departure: Departure.removed,
);

ClosureMemberRow _left(String id) => ClosureMemberRow(
  userId: id,
  activeAtOpen: true,
  departure: Departure.voluntary,
);

DateTime? _earlyCloseAt(List<ClosureMemberRow> members) =>
    ClosureCase.earlyCloseAt(epoch: _epoch(), members: members);

void main() {
  group('earlyCloseAt follows the server rule', () {
    test('one or two members close without the review: no date', () {
      expect(_earlyCloseAt([_active('h1')]), isNull);
      expect(_earlyCloseAt([_active('h1'), _active('h2')]), isNull);
    });

    test('three members with a voter: the end of the 48 h grace', () {
      expect(
        _earlyCloseAt([_active('h1'), _active('h2'), _active('h3')]),
        _opened.add(const Duration(hours: 48)),
      );
      expect(
        _earlyCloseAt([_active('h1'), _removed('h2'), _removed('h3')]),
        _opened.add(const Duration(hours: 48)),
      );
    });

    test('nobody left to answer the review: no date', () {
      expect(
        _earlyCloseAt([_removed('h1'), _removed('h2'), _removed('h3')]),
        isNull,
      );
    });

    test('#489 everyone left on their own: no voter, no date', () {
      expect(_earlyCloseAt([_left('h1'), _left('h2'), _left('h3')]), isNull);
      expect(
        _earlyCloseAt([_active('h1'), _left('h2'), _left('h3')]),
        _opened.add(const Duration(hours: 48)),
      );
    });
  });

  // Guard: the date is sent exactly when Finish now can still be waiting on
  // the grace (every outcome picked, review not committed, inside 48 h).
  test('a date is sent exactly when Finish now waits on the grace', () {
    final now = _opened.add(const Duration(minutes: 1));
    final shapes = [
      [_active('h1')],
      [_active('h1'), _active('h2')],
      [_active('h1'), _active('h2'), _active('h3')],
      [_removed('h1'), _removed('h2'), _removed('h3')],
      [_active('h1'), _active('h2'), _left('h3')],
      [_left('h1'), _left('h2'), _left('h3')],
    ];
    for (final members in shapes) {
      final canCloseNow = ClosureCase.canCloseNow(
        epoch: _epoch(),
        members: members,
        outcomes: [
          for (final m in members)
            ClosureOutcomeRow(
              helperId: m.userId,
              outcome: ClosureOutcome.done,
              updatedAt: _opened,
            ),
        ],
        commits: const [],
        now: now,
      );
      expect(_earlyCloseAt(members) != null, !canCloseNow, reason: '$members');
    }
  });
}
