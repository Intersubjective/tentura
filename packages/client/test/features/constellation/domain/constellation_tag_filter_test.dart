import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/constellation/domain/constellation_tag_filter.dart';
import 'package:tentura/features/constellation/domain/entity/constellation_field.dart';

const _neighbour = 'T-neighbour';
const _helpedMe = 'T-helped-me';

/// Own tags per person: the store index, not the field snapshot.
const _ownTags = <String, Set<String>>{
  'ann': {_neighbour, _helpedMe},
  'bob': {_neighbour},
  'cid': {_helpedMe},
  'dee': {},
};

Set<String> _ownTagIdsOf(String personId) => _ownTags[personId] ?? const {};

const _people = [
  ConstellationPerson(
    id: 'ann',
    autoTagKinds: {ConstellationAutoTagKind.mutualContact},
  ),
  ConstellationPerson(
    id: 'bob',
    autoTagKinds: {
      ConstellationAutoTagKind.mutualContact,
      ConstellationAutoTagKind.iTrust,
    },
  ),
  ConstellationPerson(
    id: 'cid',
    autoTagKinds: {ConstellationAutoTagKind.trustsMe},
  ),
  ConstellationPerson(id: 'dee'),
];

Set<String> _bright(ConstellationTagFilter filter) => {
  for (final person in _people)
    if (filter.matches(person, ownTagIds: _ownTagIdsOf(person.id))) person.id,
};

ConstellationTagLens _lens(ConstellationTagFilter filter) =>
    ConstellationTagLens(
      filter: filter,
      people: _people,
      ownTagIdsOf: _ownTagIdsOf,
      viewerId: 'ego',
    );




void main() {
  group('ConstellationTagFilter', () {
    test('an empty filter matches everybody', () {
      const filter = ConstellationTagFilter();

      expect(filter.isEmpty, isTrue);
      expect(_bright(filter), {'ann', 'bob', 'cid', 'dee'});
    });

    test('defaults to the "or" mode', () {
      expect(
        const ConstellationTagFilter().mode,
        ConstellationTagFilterMode.or,
      );
    });

    test('a single own tag keeps exactly the people in it', () {
      const filter = ConstellationTagFilter(selectedOwn: {_neighbour});

      expect(filter.isEmpty, isFalse);
      expect(_bright(filter), {'ann', 'bob'});
    });

    test('"or" over two own tags keeps the union', () {
      const filter = ConstellationTagFilter(
        selectedOwn: {_neighbour, _helpedMe},
      );

      expect(_bright(filter), {'ann', 'bob', 'cid'});
    });

    test('"and" over two own tags keeps exactly the intersection', () {
      const filter = ConstellationTagFilter(
        selectedOwn: {_neighbour, _helpedMe},
        mode: ConstellationTagFilterMode.and,
      );

      expect(_bright(filter), {'ann'});
    });

    test("an automatic tag matches through the person's autoTagKinds", () {
      const filter = ConstellationTagFilter(
        selectedAuto: {ConstellationAutoTagKind.iTrust},
      );

      expect(_bright(filter), {'bob'});
    });

    test('own and automatic tags combine by the mode: "or" is the union', () {
      const filter = ConstellationTagFilter(
        selectedOwn: {_helpedMe},
        selectedAuto: {ConstellationAutoTagKind.iTrust},
      );

      expect(_bright(filter), {'ann', 'bob', 'cid'});
    });

    test('own and automatic tags combine by the mode: "and" intersects', () {
      const filter = ConstellationTagFilter(
        selectedOwn: {_neighbour},
        selectedAuto: {ConstellationAutoTagKind.mutualContact},
        mode: ConstellationTagFilterMode.and,
      );

      expect(_bright(filter), {'ann', 'bob'});
    });

    test('own tags come from the store index, not the snapshot seed', () {
      const seededOnly = ConstellationPerson(
        id: 'eve',
        ownTagIds: [_neighbour],
      );
      const filter = ConstellationTagFilter(selectedOwn: {_neighbour});

      expect(filter.matches(seededOnly, ownTagIds: const {}), isFalse);
      expect(filter.matches(seededOnly, ownTagIds: {_neighbour}), isTrue);
    });
  });

  group('tag lens dim opacity', () {
    test('people and Requests outside the selection fade to 25 %', () {
      expect(kConstellationTagLensDimOpacity, 0.25);
    });
  });

  group('ConstellationTagLens', () {
    const intersection = ConstellationTagFilter(
      selectedOwn: {_neighbour, _helpedMe},
      mode: ConstellationTagFilterMode.and,
    );
    const union = ConstellationTagFilter(
      selectedOwn: {_neighbour, _helpedMe},
    );

    test('with nothing selected nothing is dimmed', () {
      final lens = _lens(const ConstellationTagFilter());

      expect(lens.isActive, isFalse);
      expect(lens.isAuthorDimmed('dee'), isFalse);
      expect(lens.isAuthorDimmed('dee'), isFalse);
    });

    test('the intersection stays bright and everybody else is dimmed', () {
      final lens = _lens(intersection);

      expect(lens.isActive, isTrue);
      expect(lens.brightPersonIds, {'ann'});
      expect(lens.isAuthorDimmed('ann'), isFalse);
      for (final id in ['bob', 'cid', 'dee']) {
        expect(lens.isAuthorDimmed(id), isTrue, reason: id);
      }
    });

    test('the union stays bright under "or"', () {
      final lens = _lens(union);

      expect(lens.brightPersonIds, {'ann', 'bob', 'cid'});
      expect(lens.isAuthorDimmed('dee'), isTrue);
      expect(lens.isAuthorDimmed('cid'), isFalse);
    });

    test('a Request follows its author', () {
      final lens = _lens(intersection);

      expect(lens.isAuthorDimmed('ann'), isFalse);
      expect(lens.isAuthorDimmed('bob'), isTrue);
    });

    test('a Post follows its author', () {
      final lens = _lens(intersection);

      expect(lens.isAuthorDimmed('ann'), isFalse);
      expect(lens.isAuthorDimmed('bob'), isTrue);
    });

    test('the viewer is never dimmed', () {
      final lens = _lens(intersection);

      expect(lens.isAuthorDimmed('ego'), isFalse);
    });

    test('a Request filter and the tag filter combine by "and"', () {
      const requests = [
        ConstellationRequest(
          id: 'r-ann',
          authorId: 'ann',
          title: 'a',
          status: 0,
        ),
        ConstellationRequest(
          id: 'r-bob',
          authorId: 'bob',
          title: 'b',
          status: 0,
        ),
        ConstellationRequest(
          id: 'r-cid',
          authorId: 'cid',
          title: 'c',
          status: 0,
        ),
      ];
      final lens = _lens(union);

      // The Request filter already dropped r-bob; the tag filter looks at the
      // author. Only what passes both stays bright.
      final bright = lens.brightRequestIds(
        requests,
        requestFilterIds: {'r-ann', 'r-cid'},
      );
      expect(bright, {'r-ann', 'r-cid'});

      final narrowed = _lens(intersection).brightRequestIds(
        requests,
        requestFilterIds: {'r-ann', 'r-cid'},
      );
      expect(narrowed, {'r-ann'});
    });

    test('with no tag selected the Request filter alone decides', () {
      const requests = [
        ConstellationRequest(
          id: 'r-ann',
          authorId: 'ann',
          title: 'a',
          status: 0,
        ),
        ConstellationRequest(
          id: 'r-dee',
          authorId: 'dee',
          title: 'd',
          status: 0,
        ),
      ];

      final bright = _lens(const ConstellationTagFilter()).brightRequestIds(
        requests,
        requestFilterIds: {'r-dee'},
      );

      expect(bright, {'r-dee'});
    });
  });
}
