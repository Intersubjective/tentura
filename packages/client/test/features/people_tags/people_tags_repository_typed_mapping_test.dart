// Pins how `PeopleTagsRepository` maps every typed GraphQL result to its
// domain entity, over the real Ferry link chain with a faked transport.

import 'package:flutter_test/flutter_test.dart';

import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

import '../../support/remote_wire_harness.dart';

Map<String, dynamic> _tag(String id, {int count = 4, int countOffField = 1}) =>
    {
      '__typename': 'v2_PersonTag',
      'id': id,
      'name': 'Neighbours $id',
      'glyph': 'N',
      'color': 3,
      'ord': 2,
      'count': count,
      'countOffField': countOffField,
    };

PersonTag _entity(String id, {int count = 4, int countOffField = 1}) =>
    PersonTag(
      id: id,
      name: 'Neighbours $id',
      glyph: 'N',
      color: 3,
      ord: 2,
      count: count,
      countOffField: countOffField,
    );

Map<String, dynamic> _state(Object? silencedUntil) => {
  '__typename': 'v2_PersonTagSuggestionState',
  'canSuggest': true,
  'disabled': false,
  'silencedUntil': silencedUntil,
};

final _responses = <String, Map<String, dynamic>>{
  'PersonTags': {
    '__typename': 'query_root',
    'personTags': [_tag('T1'), _tag('T2', count: 0, countOffField: 0)],
  },
  'PersonTagsOf': {
    '__typename': 'query_root',
    'personTagsOf': {
      '__typename': 'v2_PersonTagsOf',
      'own': ['T1', 'T2'],
      'auto': [
        {
          '__typename': 'v2_PersonAutoTagOf',
          'kind': 1,
          'n': 3,
          'direction': -1,
        },
      ],
    },
  },
  'PersonTagMemberships': {
    '__typename': 'query_root',
    'personTagMemberships': [
      {
        '__typename': 'v2_PersonTagMembers',
        'tagId': 'T1',
        'personIds': ['Ua', 'Ub'],
        'inherited': [
          {
            '__typename': 'v2_PersonTagInherited',
            'personId': 'Ua',
            'inviterId': 'Ub',
          },
          {
            '__typename': 'v2_PersonTagInherited',
            'personId': 'Ub',
            'inviterId': null,
          },
        ],
      },
      {
        '__typename': 'v2_PersonTagMembers',
        'tagId': 'T2',
        'personIds': <String>[],
        'inherited': <Object>[],
      },
    ],
  },
  'PersonAutoTags': {
    '__typename': 'query_root',
    'personAutoTags': [
      {
        '__typename': 'v2_PersonAutoTag',
        'kind': 2,
        'count': 7,
        'showInFilters': true,
      },
    ],
  },
  'PersonAutoTagMembers': {
    '__typename': 'query_root',
    'personAutoTagMembers': ['Ua', 'Ub'],
  },
  'PersonTagSuggestionState': {
    '__typename': 'query_root',
    'personTagSuggestionState': _state('2026-11-11T12:00:00+03:00'),
  },
  'PersonTagCreate': {
    '__typename': 'mutation_root',
    'personTagCreate': _tag('T3', count: 0, countOffField: 0),
  },
  'PersonTagUpdate': {
    '__typename': 'mutation_root',
    'personTagUpdate': _tag('T4'),
  },
  'PersonTagDelete': {
    '__typename': 'mutation_root',
    'personTagDelete': {
      '__typename': 'v2_PersonTagSnapshot',
      'tag': _tag('T5', count: 2),
      'memberIds': ['Ua', 'Ub'],
      'sources': [0, 1],
    },
  },
  'PersonTagRestore': {
    '__typename': 'mutation_root',
    'personTagRestore': _tag('T5', count: 2),
  },
  'PersonAutoTagPrefSet': {
    '__typename': 'mutation_root',
    'personAutoTagPrefSet': {
      '__typename': 'v2_PersonAutoTag',
      'kind': 2,
      'count': 7,
      'showInFilters': false,
    },
  },
  'PersonTagSuggestionRecord': {
    '__typename': 'mutation_root',
    'personTagSuggestionRecord': _state(null),
  },
};

Future<void> _withRepository(
  Future<void> Function(PeopleTagsRepository repository) body, {
  Map<String, Map<String, dynamic>>? responses,
}) => withRemoteWire(
  responses ?? _responses,
  <WireSent>[],
  (remote) => body(PeopleTagsRepository(remote)),
);

void main() {
  group('PeopleTagsRepository maps typed results to entities', () {
    test('personTags', () async {
      await _withRepository((repository) async {
        expect(await repository.personTags(), [
          _entity('T1'),
          _entity('T2', count: 0, countOffField: 0),
        ]);
      });
    });

    test('personTagsOf', () async {
      await _withRepository((repository) async {
        expect(
          await repository.personTagsOf('Ux'),
          const PersonTagsOf(
            own: ['T1', 'T2'],
            auto: [PersonAutoTagOf(kind: 1, n: 3, direction: -1)],
          ),
        );
      });
    });

    test('personTagMemberships', () async {
      await _withRepository((repository) async {
        expect(await repository.personTagMemberships(), const [
          PersonTagMembers(
            tagId: 'T1',
            personIds: ['Ua', 'Ub'],
            inherited: [
              PersonTagInherited(personId: 'Ua', inviterId: 'Ub'),
              PersonTagInherited(personId: 'Ub'),
            ],
          ),
          PersonTagMembers(tagId: 'T2', personIds: []),
        ]);
      });
    });

    test('personAutoTags and personAutoTagPrefSet', () async {
      await _withRepository((repository) async {
        expect(await repository.personAutoTags(), const [
          PersonAutoTag(kind: 2, count: 7, showInFilters: true),
        ]);
        expect(
          await repository.personAutoTagPrefSet(kind: 2, showInFilters: false),
          const PersonAutoTag(kind: 2, count: 7, showInFilters: false),
        );
      });
    });

    test('personAutoTagMembers', () async {
      await _withRepository((repository) async {
        expect(await repository.personAutoTagMembers(2), ['Ua', 'Ub']);
      });
    });

    test('suggestion state reads silencedUntil as UTC, or null', () async {
      await _withRepository((repository) async {
        final state = await repository.personTagSuggestionState();
        expect(
          state,
          PersonTagSuggestionState(
            canSuggest: true,
            disabled: false,
            silencedUntil: DateTime.utc(2026, 11, 11, 9),
          ),
        );
        expect(state.silencedUntil!.isUtc, isTrue);
        expect(
          await repository.personTagSuggestionRecord(
            outcome: 'dismissed',
            clientOpId: 'op-1',
          ),
          const PersonTagSuggestionState(canSuggest: true, disabled: false),
        );
      });
    });

    test('create, update, delete and restore', () async {
      await _withRepository((repository) async {
        expect(
          await repository.personTagCreate(name: 'N', clientOpId: 'op-1'),
          _entity('T3', count: 0, countOffField: 0),
        );
        expect(
          await repository.personTagUpdate(id: 'T4', clientOpId: 'op-2'),
          _entity('T4'),
        );
        final snapshot = await repository.personTagDelete(
          id: 'T5',
          clientOpId: 'op-3',
        );
        expect(
          snapshot,
          PersonTagSnapshot(
            tag: _entity('T5', count: 2),
            memberIds: const ['Ua', 'Ub'],
            sources: const [0, 1],
          ),
        );
        expect(
          await repository.personTagRestore(
            snapshot: snapshot,
            clientOpId: 'op-4',
          ),
          _entity('T5', count: 2),
        );
      });
    });
  });
}
