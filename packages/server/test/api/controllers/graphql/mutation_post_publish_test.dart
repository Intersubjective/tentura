import 'dart:typed_data';

import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_beacon_room.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_post.dart';
import 'package:tentura_server/domain/entity/beacon_kind.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/post_publish_result.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';
import 'package:tentura_server/domain/use_case/post_case.dart';

class _FakePostCase extends Fake implements PostCase {
  final calls = <Map<String, Object?>>[];

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
    required BeaconForwardPolicyValue forwardPolicy,
    Stream<Uint8List>? attachmentBytes,
    String? attachmentFilename,
    String? attachmentMimeType,
  }) async {
    calls.add({
      'authorId': authorId,
      'beaconId': beaconId,
      'body': body,
      'mentionUserIds': mentionUserIds,
      'mentionOffsets': mentionOffsets,
      'mentionLengths': mentionLengths,
      'recipientIds': recipientIds,
      'notes': notes,
      'forwardPolicy': forwardPolicy,
      'attachmentBytes': attachmentBytes,
      'attachmentFilename': attachmentFilename,
      'attachmentMimeType': attachmentMimeType,
    });
    return PostPublishResult(
      beaconId: beaconId,
      rootMessageId: 'Mroot00000001',
    );
  }
}

class _UnusedRoomCase extends Fake implements BeaconRoomCase {}

const _document = r'''
mutation Publish(
  $id: String!
  $body: String!
  $mentionUserIds: [String!]
  $mentionOffsets: [Int!]
  $mentionLengths: [Int!]
  $recipientIds: [String!]!
  $notes: String
  $forwardPolicy: Int!
  $file: Upload
) {
  postPublish(
    id: $id
    body: $body
    mentionUserIds: $mentionUserIds
    mentionOffsets: $mentionOffsets
    mentionLengths: $mentionLengths
    recipientIds: $recipientIds
    notes: $notes
    forwardPolicy: $forwardPolicy
    file: $file
  ) {
    beaconId
    rootMessageId
  }
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
              resolve: (_, __) => true,
            ),
          ),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.addAll(mutation.all),
      ),
    );
  });

  group('postPublish mutation', () {
    test('declares the publish arguments and the upload argument', () {
      final field = mutation.all.singleWhere((f) => f.name == 'postPublish');
      final names = field.inputs.map((a) => a.name).toSet();
      expect(
        names,
        containsAll([
          'id',
          'body',
          'mentionUserIds',
          'mentionOffsets',
          'mentionLengths',
          'recipientIds',
          'notes',
          'forwardPolicy',
          InputFieldUpload.fieldNullable.name,
        ]),
      );
    });

    test('declares the upload argument like roomMessageCreate does', () {
      final room = MutationBeaconRoom(beaconRoomCase: _UnusedRoomCase());
      final expected = room.roomMessageCreate.inputs.singleWhere(
        (a) => a.name == InputFieldUpload.fieldNullable.name,
      );
      final actual = mutation.all
          .singleWhere((f) => f.name == 'postPublish')
          .inputs
          .singleWhere((a) => a.name == InputFieldUpload.fieldNullable.name);
      expect(actual.type, same(expected.type));
      expect(actual.type, isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()));
    });

    test(
      'parses arguments, passes them to PostCase and returns the ids',
      () async {
        final result =
            await graphQL.parseAndExecute(
                  _document,
                  variableValues: {
                    'id': 'Bpost0000001',
                    'body': 'Hello @Ubob',
                    'mentionUserIds': ['Ubob000000001'],
                    'mentionOffsets': [6],
                    'mentionLengths': [4],
                    'recipientIds': ['Ubob000000001', 'Ucarol000001'],
                    'notes': '{"Ubob000000001":"for you","Ucarol000001":""}',
                    'forwardPolicy': 0,
                  },
                  globalVariables: {
                    kGlobalInputQueryJwt: const JwtEntity(
                      sub: 'Uauthor000001',
                    ),
                  },
                )
                as Map<String, dynamic>;

        expect(result['postPublish'], {
          'beaconId': 'Bpost0000001',
          'rootMessageId': 'Mroot00000001',
        });
        expect(postCase.calls, hasLength(1));
        final call = postCase.calls.single;
        expect(call['authorId'], 'Uauthor000001');
        expect(call['beaconId'], 'Bpost0000001');
        expect(call['body'], 'Hello @Ubob');
        expect(call['mentionUserIds'], ['Ubob000000001']);
        expect(call['mentionOffsets'], [6]);
        expect(call['mentionLengths'], [4]);
        expect(call['recipientIds'], ['Ubob000000001', 'Ucarol000001']);
        expect(call['notes'], {
          'Ubob000000001': 'for you',
          'Ucarol000001': '',
        });
        expect(call['forwardPolicy'], BeaconForwardPolicyValue.closed);
        expect(call['attachmentBytes'], isNull);
      },
    );

    test(
      'passes an uploaded attachment with its filename and mime type',
      () async {
        final bytes = Stream.value(Uint8List.fromList([1, 2, 3]));
        await graphQL.parseAndExecute(
          _document,
          variableValues: {
            'id': 'Bpost0000001',
            'body': '',
            'recipientIds': ['Ubob000000001'],
            'forwardPolicy': 1,
            'file': {'filename': 'photo.jpg', 'type': 'image/jpeg'},
          },
          globalVariables: {
            kGlobalInputQueryJwt: const JwtEntity(sub: 'Uauthor000001'),
            kGlobalInputQueryFile: bytes,
          },
        );

        final call = postCase.calls.single;
        expect(call['attachmentBytes'], same(bytes));
        expect(call['attachmentFilename'], 'photo.jpg');
        expect(call['attachmentMimeType'], 'image/jpeg');
        expect(call['forwardPolicy'], BeaconForwardPolicyValue.open);
      },
    );
  });
}
