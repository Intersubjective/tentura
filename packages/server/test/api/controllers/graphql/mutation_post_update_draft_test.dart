import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_post.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';

class _RecordingPostCase extends Fake implements PostCase {
  final updateDraftCalls = <Map<String, Object?>>[];

  /// Recorder for the Post draft update path (wired by [MutationPost.postUpdateDraft]).
  @override
  Future<String> updatePostDraft({
    required String authorId,
    required String beaconId,
    required String body,
    required BeaconForwardPolicyValue forwardPolicy,
    int? lifetimeHours,
  }) async {
    updateDraftCalls.add({
      'authorId': authorId,
      'beaconId': beaconId,
      'body': body,
      'forwardPolicy': forwardPolicy,
      'lifetimeHours': lifetimeHours,
    });
    return beaconId;
  }
}

const _beaconId = 'Bpostdraft001';
const _body = 'Saved composer text';

const _document = r'''
mutation UpdatePostDraft(
  $id: String!
  $body: String!
  $forwardPolicy: Int!
  $lifetimeHours: Int
) {
  postUpdateDraft(
    id: $id
    body: $body
    forwardPolicy: $forwardPolicy
    lifetimeHours: $lifetimeHours
  ) {
    id
  }
}
''';

void main() {
  late _RecordingPostCase postCase;
  late MutationPost mutation;
  late GraphQL graphQL;

  setUp(() {
    postCase = _RecordingPostCase();
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

  Future<Map<String, dynamic>> run(Map<String, dynamic> variables) async =>
      (await graphQL.parseAndExecute(
            _document,
            variableValues: variables,
            globalVariables: {
              kGlobalInputQueryJwt: const JwtEntity(sub: 'Uauthor000001'),
            },
          ))!
          as Map<String, dynamic>;

  group('postUpdateDraft mutation', () {
    test('is registered on MutationPost', () {
      expect(
        mutation.all.map((f) => f.name),
        contains('postUpdateDraft'),
      );
    });

    test('returns a Beacon with id and accepts the draft field arguments', () {
      final field = mutation.all.singleWhere((f) => f.name == 'postUpdateDraft');
      expect(
        field.inputs.map((a) => a.name).toSet(),
        containsAll({'id', 'body', 'forwardPolicy', 'lifetimeHours'}),
      );
      expect(field.type, same(gqlTypeBeacon.nonNullable()));
    });

    test(
      'forwards the draft body, forwarding policy and lifetime to PostCase '
      'and returns the beacon id',
      () async {
        final result = await run({
          'id': _beaconId,
          'body': _body,
          'forwardPolicy': BeaconForwardPolicyValue.open.value,
          'lifetimeHours': 48,
        });

        expect(result['postUpdateDraft'], {'id': _beaconId});
        expect(postCase.updateDraftCalls, hasLength(1));
        final call = postCase.updateDraftCalls.single;
        expect(call['authorId'], 'Uauthor000001');
        expect(call['beaconId'], _beaconId);
        expect(call['body'], _body);
        expect(call['forwardPolicy'], BeaconForwardPolicyValue.open);
        expect(call['lifetimeHours'], 48);
      },
    );
  });
}
