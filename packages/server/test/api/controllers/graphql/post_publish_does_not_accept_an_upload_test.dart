import 'dart:typed_data';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_post.dart';
import 'package:tentura_server/api/controllers/graphql/schema.dart'
    show TenturaGraphQL;
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/post_publish_result.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';

/// Records a publish so a still-accepted upload is a successful call, not a
/// crash inside the resolver.
class _RecordingPostCase extends Fake implements PostCase {
  @override
  Future<PostPublishResult> publish({
    required String authorId,
    required String beaconId,
    required String body,
    required List<String> mentionUserIds,
    required List<int> mentionOffsets,
    required List<int> mentionLengths,
    required List<String> recipientIds,
    required Map<String, String> notes,
    BeaconForwardPolicyValue? forwardPolicy,
    Stream<Uint8List>? attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
    int? lifetimeHours,
  }) async => PostPublishResult(
    beaconId: beaconId,
    rootMessageId: 'Mroot00000001',
  );
}

const _documentWithUpload = r'''
mutation Publish(
  $id: String!
  $body: String!
  $recipientIds: [String!]!
  $file: Upload
) {
  postPublish(id: $id, body: $body, recipientIds: $recipientIds, file: $file) {
    beaconId
    rootMessageId
  }
}
''';

void main() {
  late GraphQL graphQL;

  setUp(() {
    final mutation = MutationPost(postCase: _RecordingPostCase());
    // The production executor: it rejects arguments a field does not declare.
    graphQL = TenturaGraphQL(
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
      customTypes: customTypes,
    );
  });

  test('postPublish does not accept an upload', () async {
    final mutation = MutationPost(postCase: _RecordingPostCase());
    final field = mutation.all.singleWhere(
      (item) => item.name == 'postPublish',
    );
    expect(field.inputs.map((input) => input.name), isNot(contains('file')));

    await expectLater(
      graphQL.parseAndExecute(
        _documentWithUpload,
        variableValues: {
          'id': 'Bpost0000001',
          'body': 'Hello',
          'recipientIds': <String>[],
          'file': {'filename': 'photo.png', 'type': 'image/png'},
        },
        globalVariables: {
          kGlobalInputQueryJwt: const JwtEntity(sub: 'Uauthor000001'),
          kGlobalInputQueryFile: Stream.value(Uint8List.fromList([1, 2, 3])),
        },
      ),
      throwsA(isA<GraphQLException>()),
    );
  });
}
