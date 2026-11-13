import 'dart:convert';

import 'package:injectable/injectable.dart' show Environment;
import 'package:shelf_plus/shelf_plus.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart';
import 'package:tentura_server/api/controllers/graphql_controller.dart';
import 'package:tentura_server/env.dart';

// A field the schema does not define must answer a GraphQL error naming it,
// never `{"data": {}}`: a client calling a misspelled or not-yet-deployed
// mutation would otherwise take the empty answer for success.
void main() {
  var pinged = 0;
  final pair = GraphQLObjectType('ProbePair', null)
    ..fields.addAll([
      field('id', graphQLString.nonNullable()),
    ]);
  final controller = GraphqlController(
    Env(environment: Environment.test, printEnv: false),
    schema: TenturaGraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.add(
            GraphQLObjectField<dynamic, dynamic>(
              'probe',
              pair.nonNullable(),
              resolve: (_, _) => {'id': 'P1'},
            ),
          ),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.add(
            GraphQLObjectField<dynamic, dynamic>(
              'ping',
              graphQLBoolean.nonNullable(),
              resolve: (_, _) {
                pinged++;
                return true;
              },
            ),
          ),
      ),
      customTypes: customTypes,
    ),
  );

  setUp(() => pinged = 0);

  Future<Map<String, dynamic>> run(String query) async {
    final response = await controller.handler(
      Request(
        'POST',
        Uri.parse('http://localhost/api/v2/graphql'),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({'query': query}),
      ),
    );
    expect(response.statusCode, 200);
    return jsonDecode(await response.readAsString()) as Map<String, dynamic>;
  }

  void expectUnknownField(Map<String, dynamic> body, String name) {
    expect(body['data'], isNull, reason: jsonEncode(body));
    final errors = body['errors'];
    expect(errors, isA<List<Object?>>(), reason: jsonEncode(body));
    expect(
      [for (final e in errors as List<Object?>) (e! as Map)['message']],
      contains(contains(name)),
    );
  }

  group('Fields the V2 schema does not define', () {
    test('an unknown mutation answers an error naming it, and runs nothing',
        () async {
      final body = await run('mutation { ping NoSuchMutation }');
      expectUnknownField(body, 'NoSuchMutation');
      expect(pinged, 0);
    });

    test('an unknown field inside a known object answers an error', () async {
      expectUnknownField(await run('{ probe { id noSuchField } }'), 'noSuchField');
    });

    test('known fields and __typename still resolve', () async {
      final body = await run('{ probe { id __typename } }');
      expect(body['errors'], isNull, reason: jsonEncode(body));
      expect(body['data'], {
        'probe': {'id': 'P1', '__typename': 'ProbePair'},
      });
      expect((await run('mutation { ping }'))['data'], {'ping': true});
    });
  });
}
