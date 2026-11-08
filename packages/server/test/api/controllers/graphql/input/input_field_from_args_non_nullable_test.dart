import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/consts.dart';

/// `fromArgsNonNullable` contract: each helper reads a field the schema
/// declares non-null, so the executor rejects a missing or null value before
/// any resolver runs. The helpers therefore assert presence (`!`) instead of
/// substituting a sentinel; on the wire nothing changes.
void main() {
  final validId = 'B${'a' * (kIdLength - 1)}';

  group('fromArgsNonNullable returns the supplied value', () {
    test('InputFieldId', () {
      expect(InputFieldId.fromArgsNonNullable({'id': validId}), validId);
    });
    test('InputFieldContext', () {
      expect(InputFieldContext.fromArgsNonNullable({'context': 'c'}), 'c');
    });
    test('InputFieldDescription', () {
      expect(
        InputFieldDescription.fromArgsNonNullable({'description': ''}),
        '',
      );
    });
    test('InputFieldBeaconTitle', () {
      expect(InputFieldBeaconTitle.fromArgsNonNullable({'title': 't'}), 't');
    });
    test('InputFieldDisplayName', () {
      expect(
        InputFieldDisplayName.fromArgsNonNullable({'displayName': 'n'}),
        'n',
      );
    });
  });

  group('fromArgsNonNullable fails loudly on an absent value', () {
    for (final (name, read) in <(String, Object? Function())>[
      ('InputFieldId', () => InputFieldId.fromArgsNonNullable({})),
      ('InputFieldContext', () => InputFieldContext.fromArgsNonNullable({})),
      (
        'InputFieldDescription',
        () => InputFieldDescription.fromArgsNonNullable({}),
      ),
      (
        'InputFieldBeaconTitle',
        () => InputFieldBeaconTitle.fromArgsNonNullable({}),
      ),
      (
        'InputFieldDisplayName',
        () => InputFieldDisplayName.fromArgsNonNullable({}),
      ),
    ]) {
      test(name, () => expect(read, throwsA(isA<TypeError>())));
    }
  });

  group('executor rejects missing/null non-null args before the resolver', () {
    late List<Map<String, dynamic>> calls;
    late GraphQL graphQL;

    setUp(() {
      calls = [];
      graphQL = GraphQL(
        GraphQLSchema(
          queryType: GraphQLObjectType('Query', null)
            ..fields.addAll([
              GraphQLObjectField(
                'probeId',
                graphQLString.nonNullable(),
                arguments: [InputFieldId.field],
                resolve: (_, args) {
                  calls.add(args);
                  return InputFieldId.fromArgsNonNullable(args);
                },
              ),
              GraphQLObjectField(
                'probeContext',
                graphQLString.nonNullable(),
                arguments: [InputFieldContext.fieldNonNullable],
                resolve: (_, args) {
                  calls.add(args);
                  return InputFieldContext.fromArgsNonNullable(args);
                },
              ),
            ]),
        ),
      );
    });

    Future<Object?> run(String doc, [Map<String, dynamic> vars = const {}]) =>
        graphQL.parseAndExecute(doc, variableValues: vars);

    test('a supplied id reaches the resolver unchanged', () async {
      final result = await run(r'query Q($id: String!) { probeId(id: $id) }', {
        'id': validId,
      });
      expect(result, {'probeId': validId});
      expect(calls, hasLength(1));
    });

    test('missing id is a GraphQLException; resolver not called', () async {
      await expectLater(
        run('query Q { probeId }'),
        throwsA(isA<GraphQLException>()),
      );
      expect(calls, isEmpty);
    });

    test(
      'null id variable is a GraphQLException; resolver not called',
      () async {
        await expectLater(
          run(r'query Q($id: String!) { probeId(id: $id) }', {'id': null}),
          throwsA(isA<GraphQLException>()),
        );
        expect(calls, isEmpty);
      },
    );

    test(
      'missing context is a GraphQLException; resolver not called',
      () async {
        await expectLater(
          run('query Q { probeContext }'),
          throwsA(isA<GraphQLException>()),
        );
        expect(calls, isEmpty);
      },
    );

    test(
      'null context variable is a GraphQLException; resolver not called',
      () async {
        await expectLater(
          run(r'query Q($c: String!) { probeContext(context: $c) }', {
            'c': null,
          }),
          throwsA(isA<GraphQLException>()),
        );
        expect(calls, isEmpty);
      },
    );
  });
}
