import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/closure_outcome.dart';
import 'package:tentura_server/domain/closure/closure_split_eligible_members.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';

void main() {
  ClosureMemberRow member(String id, {Departure? departure}) =>
      ClosureMemberRow(userId: id, activeAtOpen: true, departure: departure);

  test('empty input gives an empty set', () {
    expect(closureSplitEligibleMembers(const [], const {}), isEmpty);
  });

  test('members not marked notDone are kept, with or without an outcome', () {
    final members = [member('U1'), member('U2'), member('U3'), member('U4')];
    final outcomes = <String, ClosureOutcome?>{
      'U1': ClosureOutcome.done,
      'U2': ClosureOutcome.cantJudge,
      'U3': null,
    };
    expect(closureSplitEligibleMembers(members, outcomes), {
      'U1',
      'U2',
      'U3',
      'U4',
    });
  });

  test('members the author marked notDone are dropped', () {
    final members = [member('U1'), member('U2')];
    final outcomes = <String, ClosureOutcome?>{
      'U1': ClosureOutcome.notDone,
      'U2': ClosureOutcome.done,
    };
    expect(closureSplitEligibleMembers(members, outcomes), {'U2'});
  });

  test('unjudged voluntary leavers (no row or null outcome) are dropped', () {
    final members = [
      member('U1', departure: Departure.voluntary),
      member('U2', departure: Departure.voluntary),
      member('U3'),
    ];
    final outcomes = <String, ClosureOutcome?>{'U2': null};
    expect(closureSplitEligibleMembers(members, outcomes), {'U3'});
  });

  test('judged voluntary leavers follow their judgement', () {
    final members = [
      member('U1', departure: Departure.voluntary),
      member('U2', departure: Departure.voluntary),
      member('U3', departure: Departure.voluntary),
    ];
    final outcomes = <String, ClosureOutcome?>{
      'U1': ClosureOutcome.done,
      'U2': ClosureOutcome.cantJudge,
      'U3': ClosureOutcome.notDone,
    };
    expect(closureSplitEligibleMembers(members, outcomes), {'U1', 'U2'});
  });

  test('removed members are not leavers: unjudged ones are kept', () {
    final members = [
      member('U1', departure: Departure.removed),
      member('U2', departure: Departure.removed),
    ];
    final outcomes = <String, ClosureOutcome?>{'U2': ClosureOutcome.notDone};
    expect(closureSplitEligibleMembers(members, outcomes), {'U1'});
  });
}
