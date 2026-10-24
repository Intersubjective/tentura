import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/people_tags/data/model/people_tags_mapper.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

void main() {
  group('people tags wire mapping', () {
    test('a tag maps to an entity with its derived counts', () {
      final tag = mapPersonTag({
        'id': 'T1',
        'name': 'Neighbours',
        'glyph': 'N',
        'color': 3,
        'ord': 2,
        'count': 5,
        'countOffField': 1,
      });

      expect(
        tag,
        const PersonTag(
          id: 'T1',
          name: 'Neighbours',
          glyph: 'N',
          color: 3,
          ord: 2,
          count: 5,
          countOffField: 1,
        ),
      );
    });

    test('memberships map to one entry per tag in order', () {
      final members = mapPersonTagMembers([
        {
          'tagId': 'T1',
          'personIds': ['Ua', 'Ub'],
        },
        {'tagId': 'T2', 'personIds': <String>[]},
      ]);

      expect(members.map((m) => m.tagId), ['T1', 'T2']);
      expect(members.first.personIds, ['Ua', 'Ub']);
      expect(members.last.personIds, isEmpty);
    });

    test('an automatic tag keeps its count and filter switch', () {
      expect(
        mapPersonAutoTag({'kind': 2, 'count': 7, 'showInFilters': true}),
        const PersonAutoTag(kind: 2, count: 7, showInFilters: true),
      );
    });

    test('an automatic tag of a person keeps number and direction', () {
      expect(
        mapPersonAutoTagOf({'kind': 1, 'n': 3, 'direction': -1}),
        const PersonAutoTagOf(kind: 1, n: 3, direction: -1),
      );
    });

    test('suggestion state parses the silence deadline as UTC', () {
      final state = mapPersonTagSuggestionState({
        'canSuggest': false,
        'disabled': false,
        'silencedUntil': '2026-11-01T10:00:00.000Z',
      });

      expect(state.canSuggest, isFalse);
      expect(state.silencedUntil, DateTime.utc(2026, 11, 1, 10));
    });

    test('suggestion state without a silence deadline has none', () {
      final state = mapPersonTagSuggestionState({
        'canSuggest': true,
        'disabled': false,
        'silencedUntil': null,
      });

      expect(state.silencedUntil, isNull);
      expect(state.canSuggest, isTrue);
    });

    test('personTagsOf maps own tag ids and automatic tags of the person', () {
      final of = mapPersonTagsOf({
        'own': ['Ta', 'Tb'],
        'auto': [
          {'kind': 1, 'n': 3, 'direction': -1},
        ],
      });

      expect(of.own, ['Ta', 'Tb']);
      expect(of.auto, [const PersonAutoTagOf(kind: 1, n: 3, direction: -1)]);
    });

    test('personTagsOf with nothing maps to empty lists', () {
      final of = mapPersonTagsOf({'own': <String>[], 'auto': <Object>[]});

      expect(of.own, isEmpty);
      expect(of.auto, isEmpty);
    });

    test('automatic tag members map to a list of person ids', () {
      expect(mapPersonAutoTagMembers(['Ua', 'Ub']), ['Ua', 'Ub']);
      expect(mapPersonAutoTagMembers(<String>[]), isEmpty);
    });

    test(
      'a deleted tag snapshot keeps the tag and its members with sources',
      () {
        final snapshot = mapPersonTagSnapshot({
          'tag': {
            'id': 'T1',
            'name': 'Neighbours',
            'glyph': 'N',
            'color': 3,
            'ord': 2,
            'count': 0,
            'countOffField': 0,
          },
          'memberIds': ['Ua', 'Ub'],
          'sources': [0, 1],
        });

        expect(snapshot.tag.id, 'T1');
        expect(snapshot.memberIds, ['Ua', 'Ub']);
        expect(snapshot.sources, [0, 1]);
      },
    );

    test('a snapshot converts back to the restore wire input', () {
      const snapshot = PersonTagSnapshot(
        tag: PersonTag(id: 'T1', name: 'N', glyph: 'N', color: 3, ord: 2),
        memberIds: ['Ua'],
        sources: [0],
      );

      final wire = personTagSnapshotToWire(snapshot);

      expect(wire['memberIds'], ['Ua']);
      expect(wire['sources'], [0]);
      expect((wire['tag']! as Map)['id'], 'T1');
    });

    test('a membership op converts to the apply wire input', () {
      const op = PersonTagMemberOp(tagId: 'Ta', personId: 'Ub', add: false);

      expect(personTagMemberOpToWire(op), {
        'tagId': 'Ta',
        'personId': 'Ub',
        'add': false,
        'source': isA<int>(),
      });
    });
  });
}
