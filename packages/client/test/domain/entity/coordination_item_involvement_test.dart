import 'package:test/test.dart';

import 'package:tentura/domain/entity/coordination_item.dart';

final _t = DateTime.utc(2026, 6, 1);

CoordinationItem _item({
  required String id,
  required CoordinationItemKind kind,
  String creatorId = 'creator',
  String? targetPersonId,
  CoordinationItemStatus status = CoordinationItemStatus.open,
}) =>
    CoordinationItem(
      id: id,
      beaconId: 'B1',
      kind: kind,
      status: status,
      creatorId: creatorId,
      createdAt: _t,
      updatedAt: _t,
      targetPersonId: targetPersonId,
    );

void main() {
  group('hasDirectedParties', () {
    test('ask promise blocker are directed', () {
      expect(CoordinationItemKind.ask.hasDirectedParties, isTrue);
      expect(CoordinationItemKind.promise.hasDirectedParties, isTrue);
      expect(CoordinationItemKind.blocker.hasDirectedParties, isTrue);
    });

    test('plan is not directed', () {
      expect(CoordinationItemKind.plan.hasDirectedParties, isFalse);
    });
  });

  group('directInvolvementAsSourceOrTarget', () {
    test('ask creator matches', () {
      final item = _item(id: 'a1', kind: CoordinationItemKind.ask);
      expect(item.directInvolvementAsSourceOrTarget('creator'), isTrue);
    });

    test('ask target matches', () {
      final item = _item(
        id: 'a1',
        kind: CoordinationItemKind.ask,
        targetPersonId: 'target',
      );
      expect(item.directInvolvementAsSourceOrTarget('target'), isTrue);
    });

    test('ask unrelated user does not match', () {
      final item = _item(
        id: 'a1',
        kind: CoordinationItemKind.ask,
        targetPersonId: 'target',
      );
      expect(item.directInvolvementAsSourceOrTarget('other'), isFalse);
    });

    test('promise creator and open target match', () {
      final asCreator = _item(id: 'p1', kind: CoordinationItemKind.promise);
      expect(asCreator.directInvolvementAsSourceOrTarget('creator'), isTrue);

      final asTarget = _item(
        id: 'p2',
        kind: CoordinationItemKind.promise,
        targetPersonId: 'acceptor',
      );
      expect(asTarget.directInvolvementAsSourceOrTarget('acceptor'), isTrue);
    });

    test('blocker creator-only matches', () {
      final item = _item(id: 'b1', kind: CoordinationItemKind.blocker);
      expect(item.directInvolvementAsSourceOrTarget('creator'), isTrue);
      expect(item.directInvolvementAsSourceOrTarget('other'), isFalse);
    });

    test('plan returns false', () {
      final plan = _item(id: 'pl', kind: CoordinationItemKind.plan);
      expect(plan.directInvolvementAsSourceOrTarget('creator'), isFalse);
    });
  });

  group('involvesUserAsSourceOrTarget', () {
    test('mirrors direct involvement for ask', () {
      final item = _item(
        id: 'a1',
        kind: CoordinationItemKind.ask,
        targetPersonId: 'me',
      );
      expect(item.involvesUserAsSourceOrTarget('me'), isTrue);
      expect(item.involvesUserAsSourceOrTarget('other'), isFalse);
    });
  });

  group('filterActiveItemsForUser', () {
    test('returns all when forMeOnly is false', () {
      final items = [
        _item(id: 'a1', kind: CoordinationItemKind.ask),
        _item(id: 'a2', kind: CoordinationItemKind.ask, creatorId: 'other'),
      ];
      expect(
        filterActiveItemsForUser(
          openItems: items,
          userId: 'creator',
          forMeOnly: false,
        ),
        items,
      );
    });

    test('filters to items involving user', () {
      final mine = _item(id: 'a1', kind: CoordinationItemKind.ask);
      final other = _item(
        id: 'a2',
        kind: CoordinationItemKind.ask,
        creatorId: 'stranger',
        targetPersonId: 'someone',
      );
      final open = [mine, other];
      final filtered = filterActiveItemsForUser(
        openItems: open,
        userId: 'creator',
        forMeOnly: true,
      );
      expect(filtered, [mine]);
    });

    test('focus bypass keeps excluded item', () {
      final other = _item(
        id: 'a2',
        kind: CoordinationItemKind.ask,
        creatorId: 'stranger',
        targetPersonId: 'someone',
      );
      final filtered = filterActiveItemsForUser(
        openItems: [other],
        userId: 'me',
        forMeOnly: true,
        alwaysIncludeItemId: 'a2',
      );
      expect(filtered, [other]);
    });
  });
}
