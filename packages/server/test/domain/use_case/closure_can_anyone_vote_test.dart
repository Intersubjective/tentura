import 'package:test/test.dart';

import 'package:tentura_server/domain/closure/closure_entities.dart';
import 'package:tentura_server/domain/closure/membership_reducer.dart';
import 'package:tentura_server/domain/use_case/closure_case.dart';

// #733 (Vadim, A): close opens a final check only when someone can vote in
// it; otherwise it settles the epoch at once. A voter supports among at least
// two colleagues, so that takes three members and one voter among them.

ClosureMemberInsert _m(
  String id, {
  bool active = true,
  Departure? departure,
}) => ClosureMemberInsert(
  userId: id,
  activeAtOpen: active,
  departure: departure,
);

void main() {
  group('ClosureCase.canAnyoneVote', () {
    test('one or two members: nobody can vote', () {
      expect(ClosureCase.canAnyoneVote([_m('a')]), isFalse);
      expect(ClosureCase.canAnyoneVote([_m('a'), _m('b')]), isFalse);
    });

    test('three active members: they can vote', () {
      expect(ClosureCase.canAnyoneVote([_m('a'), _m('b'), _m('c')]), isTrue);
    });

    test('three members, one voter left: still a vote', () {
      expect(
        ClosureCase.canAnyoneVote([
          _m('a'),
          _m('b', departure: Departure.voluntary),
          _m('c', active: false),
        ]),
        isTrue,
      );
    });

    test('three members, none a voter: nobody can vote', () {
      expect(
        ClosureCase.canAnyoneVote([
          _m('a', departure: Departure.voluntary),
          _m('b', departure: Departure.removed),
          _m('c', active: false),
        ]),
        isFalse,
      );
    });
  });
}
