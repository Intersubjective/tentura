@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';

// The client generates its GraphQL types from its copy of the schema, so the
// Request results line and the Field highlight can only draw the help path
// if `path` is both served and present in that copy.
void main() {
  test('the help path result serves an ordered path of named or anonymous '
      'nodes', () {
    final fields = {
      for (final f in gqlTypeForwardGraphResult.fields) f.name: f,
    };
    expect(fields.keys, containsAll(['edges', 'path']));
    expect(fields['path']!.type.toString(), contains('['));
  });

  test('the served help path schema permits anonymous identities and requires '
      'an integer anonymous count', () {
    final fields = {
      for (final field in gqlTypeForwardGraphResult.fields) field.name: field,
    };
    expect(fields, contains('path'));
    var type = fields['path']!.type;
    if (type is GraphQLNonNullableType) type = type.ofType;
    expect(type, isA<GraphQLListType<dynamic, dynamic>>());
    type = (type as GraphQLListType).ofType;
    if (type is GraphQLNonNullableType) type = type.ofType;
    expect(type, isA<GraphQLObjectType>());
    final nodeFields = {
      for (final field in (type as GraphQLObjectType).fields)
        field.name: field.type.toString(),
    };
    expect(nodeFields, containsPair('userId', 'String'));
    expect(nodeFields, containsPair('displayName', 'String'));
    expect(nodeFields, containsPair('anonymousCount', 'Int!'));
  });

  test('client codegen can select the ordered help path with names and '
      'anonymous counts', () {
    final schema = File(
      '../client/lib/data/gql/schema.graphql',
    ).readAsStringSync();

    String body(String name) {
      final declaration = schema.split(RegExp('type $name\\s*\\{'));
      expect(
        declaration,
        hasLength(2),
        reason: 'type $name must be declared once for client codegen',
      );
      return declaration.last.split('\n}').first;
    }

    String fieldType(String typeBody, String field) {
      final lines = typeBody
          .split('\n')
          .where((line) => line.trimLeft().startsWith('$field:'))
          .toList();
      expect(lines, hasLength(1), reason: '$field must be selectable');
      return lines.single.split(':').last.trim();
    }

    String named(String type) => type.replaceAll(RegExp(r'[\[\]!]'), '').trim();

    final result = body('v2_ForwardGraphResult');
    fieldType(result, 'edges');
    final pathType = fieldType(result, 'path');
    expect(pathType, startsWith('['), reason: 'path is an ordered list');
    expect(pathType, endsWith('!'), reason: 'path is always present');

    final node = body(named(pathType));
    expect(
      fieldType(node, 'userId'),
      'String',
      reason: 'anonymous (blocked) nodes carry no id',
    );
    expect(
      fieldType(node, 'displayName'),
      'String',
      reason: 'anonymous (blocked) nodes carry no name',
    );
    expect(fieldType(node, 'anonymousCount'), 'Int!');
  });
}
