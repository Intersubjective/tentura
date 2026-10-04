import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_post.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';

class _FakePostCase extends Fake implements PostCase {
  final calls = <({String action, String userId, String beaconId})>[];

  ExceptionBase? failWith;

  @override
  Future<void> leave({required String userId, required String beaconId}) async {
    calls.add((action: 'leave', userId: userId, beaconId: beaconId));
    if (failWith != null) throw failWith!;
  }

  @override
  Future<void> returnTo({
    required String userId,
    required String beaconId,
  }) async {
    calls.add((action: 'returnTo', userId: userId, beaconId: beaconId));
    if (failWith != null) throw failWith!;
  }
}

const _viewer = 'Uviewer000001';
const _beaconId = 'Bpost0000001';

const _leaveDocument = r'''
mutation Leave($id: String!) {
  postLeave(id: $id)
}
''';

const _returnDocument = r'''
mutation Return($id: String!) {
  postReturn(id: $id)
}
''';

void main() {
  late _FakePostCase postCase;
  late MutationPost mutation;
  late GraphQL graphQL;

  GraphQLObjectField<dynamic, dynamic> field(String name) =>
      mutation.all.singleWhere((f) => f.name == name);

  Future<Map<String, dynamic>> run(
    String document, {
    String? sub = _viewer,
    String id = _beaconId,
  }) async =>
      await graphQL.parseAndExecute(
            document,
            variableValues: {'id': id},
            globalVariables: {
              if (sub != null) kGlobalInputQueryJwt: JwtEntity(sub: sub),
            },
          )
          as Map<String, dynamic>;

  setUp(() {
    postCase = _FakePostCase();
    mutation = MutationPost(postCase: postCase);
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.add(
            GraphQLObjectField(
              '_health',
              graphQLBoolean.nonNullable(),
              resolve: (_, _) => true,
            ),
          ),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.addAll(mutation.all),
      ),
    );
  });

  group('postLeave and postReturn mutations', () {
    test('are registered next to postPublish by the default constructor', () {
      final names = MutationPost().all.map((f) => f.name);

      expect(names, containsAll(['postPublish', 'postLeave', 'postReturn']));
    });

    for (final name in ['postLeave', 'postReturn']) {
      test('$name takes a required id and returns a required Boolean', () {
        final mutationField = field(name);

        expect(mutationField.inputs.map((a) => a.name), ['id']);
        expect(
          mutationField.inputs.single.type,
          isA<GraphQLNonNullableType<dynamic, dynamic>>(),
        );
        expect(
          mutationField.type,
          isA<GraphQLNonNullableType<dynamic, dynamic>>(),
        );
        expect(
          (mutationField.type as GraphQLNonNullableType<dynamic, dynamic>)
              .ofType
              .name,
          'Boolean',
        );
      });
    }

    test('postLeave delegates to PostCase.leave as the caller', () async {
      final result = await run(_leaveDocument);

      expect(result['postLeave'], isTrue);
      expect(postCase.calls, [
        (action: 'leave', userId: _viewer, beaconId: _beaconId),
      ]);
    });

    test('postReturn delegates to PostCase.returnTo as the caller', () async {
      final result = await run(_returnDocument);

      expect(result['postReturn'], isTrue);
      expect(postCase.calls, [
        (action: 'returnTo', userId: _viewer, beaconId: _beaconId),
      ]);
    });

    test('takes the user from the credentials, never from arguments', () async {
      await run(_leaveDocument, sub: 'Uanother00001');
      await run(_returnDocument, sub: 'Uanother00001');

      expect(postCase.calls.map((c) => c.userId), [
        'Uanother00001',
        'Uanother00001',
      ]);
    });

    test('a refusal from PostCase is not reported as success', () async {
      postCase.failWith = const UnauthorizedException();

      await expectLater(run(_leaveDocument), throwsA(anything));
      await expectLater(run(_returnDocument), throwsA(anything));
    });

    test('without credentials PostCase is never called', () async {
      await expectLater(run(_leaveDocument, sub: null), throwsA(anything));
      await expectLater(run(_returnDocument, sub: null), throwsA(anything));

      expect(postCase.calls, isEmpty);
    });
  });
}
