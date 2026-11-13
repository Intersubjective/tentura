import 'package:graphql_server2/graphql_server2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/schema.dart';

GraphQL _schema() => TenturaGraphQL(
  GraphQLSchema(
    queryType: GraphQLObjectType('Query', 'Query root')
      ..fields.add(
        field('ping', graphQLString, resolve: (_, _) => 'pong'),
      ),
    mutationType: GraphQLObjectType('Mutation', 'Mutation root')
      ..fields.add(
        field('doIt', graphQLString, resolve: (_, _) => 'done'),
      ),
  ),
);

void main() {
  test('a known mutation field executes', () async {
    expect(
      await _schema().parseAndExecute('mutation { doIt }'),
      {'doIt': 'done'},
    );
  });

  test('an unknown mutation field is an error, not empty data', () {
    expect(
      _schema().parseAndExecute('mutation { noSuchMutation }'),
      throwsA(
        isA<GraphQLException>().having(
          (e) => e.toJson().toString(),
          'message',
          contains('Cannot query field "noSuchMutation" on type "Mutation"'),
        ),
      ),
    );
  });

  test('an unknown query field is an error', () {
    expect(
      _schema().parseAndExecute('{ ping nope }'),
      throwsA(isA<GraphQLException>()),
    );
  });
}
