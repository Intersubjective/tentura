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
  final shortenCalls =
      <({String userId, String beaconId, DateTime expiresAt})>[];
  final closeCalls = <({String userId, String beaconId})>[];
  Exception? failWith;

  @override
  Future<void> shorten({
    required String userId,
    required String beaconId,
    required DateTime expiresAt,
  }) async {
    if (failWith != null) throw failWith!;
    shortenCalls.add((
      userId: userId,
      beaconId: beaconId,
      expiresAt: expiresAt,
    ));
  }

  @override
  Future<void> close({
    required String userId,
    required String beaconId,
  }) async {
    if (failWith != null) throw failWith!;
    closeCalls.add((userId: userId, beaconId: beaconId));
  }
}

const _shortenDocument = r'''
mutation Shorten($id: String!, $expiresAt: String!) {
  postShorten(id: $id, expiresAt: $expiresAt)
}
''';

const _closeDocument = r'''
mutation Close($id: String!) {
  postClose(id: $id)
}
''';

void main() {
  late _FakePostCase postCase;
  late MutationPost mutation;
  late GraphQL graphQL;

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

  Future<Map<String, dynamic>> run(
    String document,
    Map<String, dynamic> variables,
  ) async =>
      (await graphQL.parseAndExecute(
            document,
            variableValues: variables,
            globalVariables: {
              kGlobalInputQueryJwt: const JwtEntity(sub: 'Uauthor000001'),
            },
          ))!
          as Map<String, dynamic>;

  group('postShorten mutation', () {
    test(
      'is declared with a required id and expiresAt and returns a Boolean',
      () {
        final field = mutation.all.singleWhere((f) => f.name == 'postShorten');

        expect(field.inputs.map((a) => a.name).toSet(), {'id', 'expiresAt'});
        expect(
          field.inputs.every((a) => a.type is GraphQLNonNullableType),
          isTrue,
        );
        expect(field.type.toString(), 'Boolean!');
      },
    );

    test(
      'passes the caller, the Post and the parsed end to PostCase',
      () async {
        final result = await run(_shortenDocument, {
          'id': 'Bpost0000001',
          'expiresAt': '2026-10-26T18:30:00Z',
        });

        expect(result['postShorten'], isTrue);
        expect(postCase.shortenCalls, hasLength(1));
        final call = postCase.shortenCalls.single;
        expect(call.userId, 'Uauthor000001');
        expect(call.beaconId, 'Bpost0000001');
        expect(call.expiresAt, DateTime.utc(2026, 10, 26, 18, 30));
        expect(call.expiresAt.isUtc, isTrue);
      },
    );

    test('reads an end with an offset as the same instant', () async {
      await run(_shortenDocument, {
        'id': 'Bpost0000001',
        'expiresAt': '2026-10-26T20:30:00+02:00',
      });

      expect(
        postCase.shortenCalls.single.expiresAt,
        DateTime.utc(2026, 10, 26, 18, 30),
      );
    });

    test('surfaces a refused extension and does not report success', () async {
      postCase.failWith = const PostLifetimeExtendException();

      await expectLater(
        run(_shortenDocument, {
          'id': 'Bpost0000001',
          'expiresAt': '2026-10-26T18:30:00Z',
        }),
        throwsA(isA<PostLifetimeExtendException>()),
      );
    });
  });

  group('postClose mutation', () {
    test('is declared with a required id and returns a Boolean', () {
      final field = mutation.all.singleWhere((f) => f.name == 'postClose');

      expect(field.inputs.map((a) => a.name).toSet(), {'id'});
      expect(
        field.inputs.single.type,
        isA<GraphQLNonNullableType<dynamic, dynamic>>(),
      );
      expect(field.type.toString(), 'Boolean!');
    });

    test('passes the caller and the Post to PostCase', () async {
      final result = await run(_closeDocument, {'id': 'Bpost0000001'});

      expect(result['postClose'], isTrue);
      expect(postCase.closeCalls, hasLength(1));
      expect(postCase.closeCalls.single.userId, 'Uauthor000001');
      expect(postCase.closeCalls.single.beaconId, 'Bpost0000001');
    });

    test('surfaces a Post that is no longer open', () async {
      postCase.failWith = const PostNotOpenException();

      await expectLater(
        run(_closeDocument, {'id': 'Bpost0000001'}),
        throwsA(isA<PostNotOpenException>()),
      );
    });
  });
}
