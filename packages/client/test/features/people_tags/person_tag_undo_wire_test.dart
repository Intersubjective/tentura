import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:gql/ast.dart';
import 'package:gql/language.dart';
import 'package:tentura/features/people_tags/data/repository/people_tags_repository.dart';
import 'package:tentura/features/people_tags/domain/entity/people_tags_entities.dart';

import '../../support/remote_wire_harness.dart';

const _tag = {
  'id': 'Tneighbours',
  'name': 'Neighbours',
  'glyph': 'N',
  'color': 3,
  'ord': 2,
};
const _countedTag = {
  '__typename': 'v2_PersonTag',
  ..._tag,
  'count': 3,
  'countOffField': 1,
};
const _members = [
  {
    'kind': 'person',
    'id': 'Udirect000001',
    'source': 2,
    'membershipId': '0691052e-2cab-4a7f-bb1b-74e3d09e116c',
  },
  {
    'kind': 'person',
    'id': 'Umerged000001',
    'source': 0,
    'membershipId': 'dd1fd6dc-5254-4162-9513-370e2ec3cab9',
  },
  {
    'kind': 'phantom',
    'id': 'PHprivate0001',
    'source': 0,
    'membershipId': '3fad514a-8b97-44e8-be73-59cc4ce0d22b',
  },
];

void main() {
  test(
    'deleting a people tag returns the original identity of every member',
    () async {
      await _withUndoWire((repository, _) async {
        final snapshot = await _delete(repository);
        expect(
          snapshot.tag,
          const PersonTag(
            id: 'Tneighbours',
            name: 'Neighbours',
            glyph: 'N',
            color: 3,
            ord: 2,
            count: 3,
            countOffField: 1,
          ),
        );
        expect([
          for (final member in snapshot.members)
            {
              'kind': member.kind.name,
              'id': member.id,
              'source': member.source,
              'membershipId': member.membershipId,
            },
        ], _members);
      });
    },
  );

  test(
    'restoring a deleted people tag sends every membership in snapshot order',
    () async {
      await _withUndoWire((repository, sent) async {
        final snapshot = await _delete(repository);
        final restored = await repository.personTagRestore(
          snapshot: snapshot,
          clientOpId: 'restore-neighbours',
        );

        expect(restored, snapshot.tag);
        expect(sent.map((request) => request.operationName), [
          'PersonTagDelete',
          'PersonTagRestore',
        ]);
        expect(sent.last.variables, {
          'clientOpId': 'restore-neighbours',
          'snapshot': {'tag': _tag, 'members': _members},
        });
      });
    },
  );

  test(
    'the client GraphQL schema accepts complete membership snapshots for Undo',
    () {
      final schema = parseString(
        File('lib/data/gql/schema.graphql').readAsStringSync(),
      ).definitions;
      final input = schema
          .whereType<InputObjectTypeDefinitionNode>()
          .singleWhere(
            (node) => node.name.value == 'v2_PersonTagSnapshotInput',
          );
      expect(
        input.fields.map((field) => field.name.value),
        unorderedEquals(['tag', 'members']),
      );
      final members = input.fields.singleWhere(
        (field) => field.name.value == 'members',
      );
      expect(members.type, isA<ListTypeNode>());
      final memberType = (members.type as ListTypeNode).type as NamedTypeNode;
      final member = schema
          .whereType<InputObjectTypeDefinitionNode>()
          .singleWhere(
            (node) => node.name.value == memberType.name.value,
          );
      expect(
        member.fields.map((field) => field.name.value),
        unorderedEquals(['kind', 'id', 'source', 'membershipId']),
      );
    },
  );
}

Future<PersonTagSnapshot> _delete(PeopleTagsRepository repository) =>
    repository.personTagDelete(
      id: 'Tneighbours',
      clientOpId: 'delete-neighbours',
    );

Future<void> _withUndoWire(
  Future<void> Function(PeopleTagsRepository, List<WireSent>) exercise,
) async {
  final sent = <WireSent>[];
  await withRemoteWire(
    {
      'PersonTagDelete': {
        '__typename': 'mutation_root',
        'personTagDelete': {
          '__typename': 'v2_PersonTagSnapshot',
          'tag': _countedTag,
          'members': [
            for (final member in _members)
              {'__typename': 'v2_PersonTagSnapshotMember', ...member},
          ],
        },
      },
      'PersonTagRestore': {
        '__typename': 'mutation_root',
        'personTagRestore': _countedTag,
      },
    },
    sent,
    (remote) => exercise(PeopleTagsRepository(remote), sent),
    selectResponse: _selectDeleteFields,
  );
}

// Like a GraphQL server, return only the selected snapshot and member fields.
Map<String, dynamic> _selectDeleteFields(
  String query,
  Map<String, dynamic> data,
) {
  final snapshot = data['personTagDelete'];
  if (snapshot is! Map<String, dynamic>) return data;
  final operation = parseString(
    query,
  ).definitions.whereType<OperationDefinitionNode>().single;
  final selection = operation.selectionSet.selections
      .whereType<FieldNode>()
      .singleWhere((node) => node.name.value == 'personTagDelete');
  final fields = selection.selectionSet!.selections.whereType<FieldNode>();
  return {
    ...data,
    'personTagDelete': {
      '__typename': snapshot['__typename'],
      for (final field in fields)
        field.name.value: field.name.value == 'members'
            ? [
                for (final member
                    in snapshot['members'] as List<Map<String, Object>>)
                  {
                    '__typename': member['__typename'],
                    for (final selected
                        in field.selectionSet!.selections
                            .whereType<FieldNode>())
                      selected.name.value: member[selected.name.value],
                  },
              ]
            : snapshot[field.name.value],
    },
  };
}
