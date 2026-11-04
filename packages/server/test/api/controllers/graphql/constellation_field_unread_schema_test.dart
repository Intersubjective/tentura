@Tags(['repo-files'])
library;

import 'dart:io';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';

void main() {
  group('Field unread flag is available to GraphQL clients', () {
    final graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', null)
          ..fields.add(
            GraphQLObjectField(
              'field',
              gqlTypeConstellationField,
              resolve: (_, args) => null,
            ),
          ),
      ),
      customTypes: customTypes,
    );

    for (final type in ['ConstellationRequest', 'ConstellationPost']) {
      test(
        '$type exposes has_unread as a Boolean through introspection',
        () async {
          final result =
              await graphQL.parseAndExecute('''
query {
  __type(name: "$type") {
    fields { name type { name kind ofType { name kind } } }
  }
}
''')
                  as Map<String, dynamic>;
          expect(result['errors'], isNull);
          expect(result['__type'], isA<Map<String, dynamic>>());
          final definition = result['__type'] as Map;
          final fields = (definition['fields'] as List)
              .cast<Map<String, dynamic>>();
          final unread = fields.where((field) => field['name'] == 'has_unread');
          expect(unread, hasLength(1), reason: '$type must publish has_unread');
          final declared = unread.single['type'] as Map;
          final scalar = declared['kind'] == 'NON_NULL'
              ? declared['ofType'] as Map
              : declared;
          expect(scalar['kind'], 'SCALAR');
          expect(scalar['name'], 'Boolean');
        },
      );

      test('the client codegen schema exposes has_unread on v2_$type', () {
        final schema = File(
          '../client/lib/data/gql/schema.graphql',
        ).readAsStringSync();
        final definition = RegExp(
          'type v2_$type\\s*\\{([^}]+)\\}',
          multiLine: true,
        ).firstMatch(schema);
        expect(
          definition,
          isNotNull,
          reason: 'Client schema must contain v2_$type',
        );
        expect(
          definition!.group(1),
          matches(
            RegExp(r'^\s*has_unread\s*:\s*Boolean!?\s*$', multiLine: true),
          ),
          reason:
              'Client codegen must be able to select the Boolean has_unread field on v2_$type',
        );
      });
    }
  });
}
