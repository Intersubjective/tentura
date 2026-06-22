import 'package:test/test.dart';

import 'package:tentura/domain/entity/coordination_item.dart';

final _t = DateTime.utc(2026, 6, 1);

CoordinationItem _item({
  required String id,
  required CoordinationItemKind kind,
  String creatorId = 'creator',
  String? targetPersonId,
  String? targetItemId,
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
      targetItemId: targetItemId,
    );

void main() {
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

    test('plan and resolution return false', () {
      final plan = _item(id: 'pl', kind: CoordinationItemKind.plan);
      final resolution = _item(id: 'r1', kind: CoordinationItemKind.resolution);
      expect(plan.directInvolvementAsSourceOrTarget('creator'), isFalse);
      expect(resolution.directInvolvementAsSourceOrTarget('creator'), isFalse);
    });
  });

  group('involvesUserAsSourceOrTarget', () {
    test('resolution linked to ask where user is target', () {
      final parent = _item(
        id: 'ask-1',
        kind: CoordinationItemKind.ask,
        targetPersonId: 'me',
      );
      final resolution = _item(
        id: 'res-1',
        kind: CoordinationItemKind.resolution,
        creatorId: 'reviewer',
        targetItemId: 'ask-1',
      );
      expect(
        resolution.involvesUserAsSourceOrTarget(
          'me',
          resolutionParent: parent,
        ),
        isTrue,
      );
    });

    test('resolution linked to ask where user is creator', () {
      final parent = _item(
        id: 'ask-1',
        kind: CoordinationItemKind.ask,
        creatorId: 'me',
        targetPersonId: 'other',
      );
      final resolution = _item(
        id: 'res-1',
        kind: CoordinationItemKind.resolution,
        creatorId: 'reviewer',
        targetItemId: 'ask-1',
      );
      expect(
        resolution.involvesUserAsSourceOrTarget(
          'me',
          resolutionParent: parent,
        ),
        isTrue,
      );
    });

    test('resolution without matching parent does not match', () {
      final resolution = _item(
        id: 'res-1',
        kind: CoordinationItemKind.resolution,
        creatorId: 'reviewer',
        targetItemId: 'ask-1',
      );
      expect(
        resolution.involvesUserAsSourceOrTarget('me'),
        isFalse,
      );
    });

    test('resolution creator matches directly', () {
      final resolution = _item(
        id: 'res-1',
        kind: CoordinationItemKind.resolution,
        creatorId: 'me',
      );
      expect(resolution.involvesUserAsSourceOrTarget('me'), isTrue);
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
          lookupItems: items,
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
        lookupItems: open,
        userId: 'creator',
        forMeOnly: true,
      );
      expect(filtered, [mine]);
    });

    test('resolves parent from closed lookup items', () {
      final closedParent = _item(
        id: 'ask-closed',
        kind: CoordinationItemKind.ask,
        targetPersonId: 'me',
        status: CoordinationItemStatus.resolved,
      );
      final resolution = _item(
        id: 'res-1',
        kind: CoordinationItemKind.resolution,
        creatorId: 'reviewer',
        targetItemId: 'ask-closed',
      );
      final filtered = filterActiveItemsForUser(
        openItems: [resolution],
        lookupItems: [closedParent, resolution],
        userId: 'me',
        forMeOnly: true,
      );
      expect(filtered, [resolution]);
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
        lookupItems: [other],
        userId: 'me',
        forMeOnly: true,
        alwaysIncludeItemId: 'a2',
      );
      expect(filtered, [other]);
    });
  });
}
