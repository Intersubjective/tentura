import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_room_baton.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/entity/room_baton.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/beacon_room_repository_port.dart';
import 'package:tentura_server/domain/port/room_baton_repository_port.dart';
import 'package:tentura_server/domain/use_case/room_baton_case.dart';

/// Unwraps `nonNullable()`/list wrappers to the innermost named type.
String _baseTypeName(GraphQLType<dynamic, dynamic> type) {
  var t = type;
  while (true) {
    if (t is GraphQLNonNullableType) {
      t = t.ofType;
    } else if (t is GraphQLListType) {
      t = t.ofType;
    } else {
      return t.name ?? t.toString();
    }
  }
}

GraphQL _batonGraphQL(MutationRoomBaton mutation) => GraphQL(
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

Future<Map<String, dynamic>> _execute({
  required GraphQL graphQL,
  required String document,
  Map<String, dynamic> variables = const {},
  JwtEntity? jwt,
}) async {
  final result = await graphQL.parseAndExecute(
    document,
    variableValues: variables,
    globalVariables: {
      if (jwt != null) kGlobalInputQueryJwt: jwt,
    },
  );
  return result as Map<String, dynamic>;
}

/// Hand-written stand-in for [RoomBatonCase]: records every call and can be
/// told to throw, so the tests see exactly what the mutation layer forwards.
final class _RecordingBatonCase extends Fake implements RoomBatonCase {
  final createCalls =
      <
        ({
          String actorId,
          String beaconId,
          String text,
          String? replyToMessageId,
          List<({String userId, int tier})> candidates,
        })
      >[];
  final respondCalls = <({String actorId, String batonId, bool canHelp})>[];
  final selectCalls = <({String actorId, String batonId, String? userId})>[];
  final cancelCalls = <({String actorId, String batonId})>[];
  final updateCalls =
      <
        ({
          String actorId,
          String batonId,
          String text,
          List<({String userId, int tier})> candidates,
        })
      >[];

  Exception? failWith;

  @override
  Future<RoomBaton> create({
    required String actorId,
    required String beaconId,
    required String text,
    required List<({String userId, int tier})> candidates,
    String? replyToMessageId,
  }) async {
    createCalls.add((
      actorId: actorId,
      beaconId: beaconId,
      text: text,
      replyToMessageId: replyToMessageId,
      candidates: candidates,
    ));
    if (failWith case final Exception e) throw e;
    return RoomBaton(
      id: _batonId,
      messageId: _newMessageId,
      beaconId: beaconId,
      authorId: actorId,
      status: BatonStatus.collecting,
      createdAt: DateTime.utc(2026, 10, 5),
    );
  }

  @override
  Future<void> update({
    required String actorId,
    required String batonId,
    required String text,
    required List<({String userId, int tier})> candidates,
  }) async {
    updateCalls.add((
      actorId: actorId,
      batonId: batonId,
      text: text,
      candidates: candidates,
    ));
    if (failWith case final Exception e) throw e;
  }

  @override
  Future<void> respond({
    required String actorId,
    required String batonId,
    required bool canHelp,
  }) async {
    respondCalls.add((actorId: actorId, batonId: batonId, canHelp: canHelp));
    if (failWith case final Exception e) throw e;
  }

  @override
  Future<void> select({
    required String actorId,
    required String batonId,
    String? userId,
  }) async {
    selectCalls.add((actorId: actorId, batonId: batonId, userId: userId));
    if (failWith case final Exception e) throw e;
  }

  @override
  Future<void> cancel({
    required String actorId,
    required String batonId,
  }) async {
    cancelCalls.add((actorId: actorId, batonId: batonId));
    if (failWith case final Exception e) throw e;
  }
}

const _beaconId = 'Bbeacon000001';
const _messageId = 'Mmessage00001';
const _newMessageId = 'Mmessage00002';
const _batonId = 'Lbaton000001';
const _author = 'Ubaton-author';
const _candidate = 'Ubaton-candidate';
const _bystander = 'Ubaton-bystander';

/// What the room read path (`batonDataJson`, per viewer) yields for the baton
/// on [_messageId]; the author sees the full list, a candidate only their own
/// answer, and a bystander only that a baton exists.
const _batonDataJsonByViewer = <String, String>{
  _author:
      '{"id":"$_batonId","status":"collecting","viewerRole":"author",'
      '"candidates":[{"userId":"$_candidate","tier":1,"response":"waiting"}]}',
  _candidate:
      '{"id":"$_batonId","status":"collecting","viewerRole":"candidate",'
      '"myResponse":"waiting"}',
  _bystander:
      '{"id":"$_batonId","status":"collecting","viewerRole":"observer"}',
};

/// Stand-in for the room read path: records who asked for which message and
/// answers with the payload computed for *that viewer*.
final class _RecordingRoomRepository extends Fake
    implements BeaconRoomRepositoryPort {
  final targetCalls =
      <({String beaconId, String messageId, String viewerUserId})>[];

  @override
  Future<Map<String, Object?>?> roomMessageTarget({
    required String beaconId,
    required String messageId,
    required String viewerUserId,
  }) async {
    targetCalls.add((
      beaconId: beaconId,
      messageId: messageId,
      viewerUserId: viewerUserId,
    ));
    return {
      'id': messageId,
      'batonDataJson': _batonDataJsonByViewer[viewerUserId],
    };
  }
}

/// Resolves a baton id to its message/beacon so respond/select can read the
/// per-viewer payload back.
final class _FakeBatonRepository extends Fake
    implements RoomBatonRepositoryPort {
  @override
  Future<RoomBaton?> getById(String batonId) async => batonId == _batonId
      ? RoomBaton(
          id: _batonId,
          messageId: _messageId,
          beaconId: _beaconId,
          authorId: _author,
          status: BatonStatus.collecting,
          createdAt: DateTime.utc(2026, 10, 5),
        )
      : null;
}

void main() {
  const authorJwt = JwtEntity(sub: _author);
  const candidateJwt = JwtEntity(sub: _candidate);

  late _RecordingBatonCase batonCase;
  late _RecordingRoomRepository roomRepository;
  late MutationRoomBaton mutation;
  late GraphQL graphQL;

  setUp(() {
    batonCase = _RecordingBatonCase();
    roomRepository = _RecordingRoomRepository();
    mutation = MutationRoomBaton(
      roomBatonCase: batonCase,
      batonRepository: _FakeBatonRepository(),
      roomRepository: roomRepository,
    );
    graphQL = _batonGraphQL(mutation);
  });

  Future<Map<String, dynamic>> run(
    String document, {
    Map<String, dynamic> variables = const {},
    JwtEntity? jwt,
  }) => _execute(
    graphQL: graphQL,
    document: document,
    variables: variables,
    jwt: jwt,
  );

  Matcher failsWith<T extends ExceptionBase>(int code) => throwsA(
    isA<T>().having((e) => e.code.codeNumber, 'code number', code),
  );

  group('schema registration', () {
    test('exposes the five baton mutations', () {
      expect(
        mutation.all.map((f) => f.name).toSet(),
        {
          'roomBatonCreate',
          'roomBatonUpdate',
          'roomBatonRespond',
          'roomBatonSelect',
          'roomBatonCancel',
        },
      );
    });

    test(
      'roomBatonCreate takes beaconId, text, optional replyTo, candidates',
      () {
        final create = mutation.all.singleWhere(
          (f) => f.name == 'roomBatonCreate',
        );
        final candidates = create.inputs.singleWhere(
          (i) => i.name == 'candidates',
        );
        expect(
          candidates.type,
          isA<GraphQLNonNullableType<dynamic, dynamic>>(),
        );
        expect(_baseTypeName(candidates.type), 'RoomBatonCandidateInput');
        for (final name in ['beaconId', 'text']) {
          expect(
            create.inputs.singleWhere((i) => i.name == name).type,
            isA<GraphQLNonNullableType<dynamic, dynamic>>(),
            reason: name,
          );
        }
        expect(
          create.inputs.singleWhere((i) => i.name == 'replyToMessageId').type,
          isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()),
        );
        expect(
          create.inputs.map((i) => i.name),
          isNot(contains('messageId')),
        );
      },
    );

    test('roomBatonCreate returns a non-null String (the message id)', () {
      final create = mutation.all.singleWhere(
        (f) => f.name == 'roomBatonCreate',
      );
      expect(create.type, isA<GraphQLNonNullableType<dynamic, dynamic>>());
      expect(_baseTypeName(create.type), 'String');
    });

    test('roomBatonUpdate takes required batonId, text and candidates', () {
      final update = mutation.all.singleWhere(
        (f) => f.name == 'roomBatonUpdate',
      );
      expect(
        update.inputs.map((i) => i.name).toSet(),
        {'batonId', 'text', 'candidates'},
      );
      for (final input in update.inputs) {
        expect(
          input.type,
          isA<GraphQLNonNullableType<dynamic, dynamic>>(),
          reason: input.name,
        );
      }
      expect(
        _baseTypeName(
          update.inputs.singleWhere((i) => i.name == 'candidates').type,
        ),
        'RoomBatonCandidateInput',
      );
    });

    test('roomBatonUpdate returns a nullable String (batonDataJson)', () {
      final update = mutation.all.singleWhere(
        (f) => f.name == 'roomBatonUpdate',
      );
      expect(
        update.type,
        isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()),
      );
      expect(_baseTypeName(update.type), 'String');
    });

    test('roomBatonSelect keeps userId optional', () {
      final select = mutation.all.singleWhere(
        (f) => f.name == 'roomBatonSelect',
      );
      expect(
        select.inputs.singleWhere((i) => i.name == 'userId').type,
        isNot(isA<GraphQLNonNullableType<dynamic, dynamic>>()),
      );
    });

    test('roomBatonCancel returns a non-null Boolean', () {
      final cancel = mutation.all.singleWhere(
        (f) => f.name == 'roomBatonCancel',
      );
      expect(cancel.type, isA<GraphQLNonNullableType<dynamic, dynamic>>());
      expect(_baseTypeName(cancel.type), 'Boolean');
    });
  });

  group('roomBatonCreate', () {
    const createDocument = r'''
      mutation Create(
        $beaconId: String!
        $text: String!
        $replyToMessageId: String
        $candidates: [RoomBatonCandidateInput!]!
      ) {
        roomBatonCreate(
          beaconId: $beaconId
          text: $text
          replyToMessageId: $replyToMessageId
          candidates: $candidates
        )
      }
    ''';

    test('uses the JWT subject as actor and maps every argument', () async {
      await run(
        createDocument,
        variables: const {
          'beaconId': _beaconId,
          'text': 'Who can bring the ladder?',
          'replyToMessageId': _messageId,
          'candidates': [
            {'userId': 'Ucandidate01', 'tier': 1},
            {'userId': 'Ucandidate02', 'tier': 3},
          ],
        },
        jwt: authorJwt,
      );

      expect(batonCase.createCalls, hasLength(1));
      final call = batonCase.createCalls.single;
      expect(call.actorId, _author);
      expect(call.beaconId, _beaconId);
      expect(call.text, 'Who can bring the ladder?');
      expect(call.replyToMessageId, _messageId);
      expect(call.candidates, [
        (userId: 'Ucandidate01', tier: 1),
        (userId: 'Ucandidate02', tier: 3),
      ]);
    });

    for (final (label, variables) in [
      ('omitted', const <String, dynamic>{}),
      ('null', const <String, dynamic>{'replyToMessageId': null}),
      ('empty', const <String, dynamic>{'replyToMessageId': ''}),
    ]) {
      // A plain `graphQLString` arg rejected a null/absent variable
      // ("Expected replyToMessageId to be a string"), which broke every baton
      // that is not a reply.
      test('an $label replyToMessageId reaches the case as null', () async {
        await run(
          createDocument,
          variables: {
            'beaconId': _beaconId,
            'text': 'Who can bring the ladder?',
            'candidates': const [
              {'userId': 'Ucandidate01', 'tier': 1},
            ],
            ...variables,
          },
          jwt: authorJwt,
        );

        expect(batonCase.createCalls.single.replyToMessageId, isNull);
      });
    }

    test('returns the new message id without a per-viewer read', () async {
      final result = await run(
        '''
          mutation {
            roomBatonCreate(
              beaconId: "Bbeacon000001"
              text: "Who can bring the ladder?"
              candidates: [{userId: "Ubaton-candidate", tier: 1}]
            )
          }
        ''',
        jwt: authorJwt,
      );

      expect(result['roomBatonCreate'], _newMessageId);
      expect(roomRepository.targetCalls, isEmpty);
    });

    test('missing text is rejected by the schema', () async {
      await expectLater(
        run(
          '''
            mutation {
              roomBatonCreate(
                beaconId: "Bbeacon000001"
                candidates: [{userId: "Ucandidate01", tier: 1}]
              )
            }
          ''',
          jwt: authorJwt,
        ),
        throwsA(isA<GraphQLException>()),
      );
      expect(batonCase.createCalls, isEmpty);
    });

    test(
      'rejects a candidate without a tier before reaching the case',
      () async {
        await expectLater(
          run(
            r'''
            mutation Create($candidates: [RoomBatonCandidateInput!]!) {
              roomBatonCreate(
                beaconId: "Bbeacon000001"
                text: "Ask"
                candidates: $candidates
              )
            }
          ''',
            variables: const {
              'candidates': [
                {'userId': 'Ucandidate01'},
              ],
            },
            jwt: authorJwt,
          ),
          throwsA(isA<GraphQLException>()),
        );
        expect(batonCase.createCalls, isEmpty);
      },
    );

    test('missing JWT is rejected without calling the case', () async {
      await expectLater(
        run('''
          mutation {
            roomBatonCreate(
              beaconId: "Bbeacon000001"
              text: "Ask"
              candidates: [{userId: "Ucandidate01", tier: 1}]
            )
          }
        '''),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(batonCase.createCalls, isEmpty);
    });

    test('case exceptions surface with their own codes', () async {
      const document = '''
        mutation {
          roomBatonCreate(
            beaconId: "Bbeacon000001"
            text: "Ask"
            candidates: [{userId: "Ucandidate01", tier: 1}]
          )
        }
      ''';
      batonCase.failWith = const BatonInvalidCandidatesException();
      await expectLater(
        run(document, jwt: authorJwt),
        failsWith<BatonInvalidCandidatesException>(1326),
      );
      batonCase.failWith = const BatonMessageNotEligibleException();
      await expectLater(
        run(document, jwt: authorJwt),
        failsWith<BatonMessageNotEligibleException>(1329),
      );
      batonCase.failWith = const RateLimitedException();
      await expectLater(
        run(document, jwt: authorJwt),
        throwsA(isA<RateLimitedException>()),
      );
    });
  });

  group('roomBatonUpdate', () {
    const updateDocument = r'''
      mutation Update(
        $batonId: String!
        $text: String!
        $candidates: [RoomBatonCandidateInput!]!
      ) {
        roomBatonUpdate(batonId: $batonId, text: $text, candidates: $candidates)
      }
    ''';

    const variables = <String, dynamic>{
      'batonId': _batonId,
      'text': 'Who can bring the big ladder?',
      'candidates': [
        {'userId': 'Ucandidate01', 'tier': 2},
        {'userId': 'Ucandidate02', 'tier': 1},
      ],
    };

    test('uses the JWT subject as actor and maps every argument', () async {
      await run(updateDocument, variables: variables, jwt: authorJwt);

      expect(batonCase.updateCalls, hasLength(1));
      final call = batonCase.updateCalls.single;
      expect(call.actorId, _author);
      expect(call.batonId, _batonId);
      expect(call.text, 'Who can bring the big ladder?');
      expect(call.candidates, [
        (userId: 'Ucandidate01', tier: 2),
        (userId: 'Ucandidate02', tier: 1),
      ]);
    });

    test('an empty text reaches the case unchanged', () async {
      await run(
        updateDocument,
        variables: {...variables, 'text': ''},
        jwt: authorJwt,
      );

      expect(batonCase.updateCalls.single.text, '');
    });

    test("returns the caller's batonDataJson read after the write", () async {
      final result = await run(
        updateDocument,
        variables: variables,
        jwt: authorJwt,
      );

      expect(result['roomBatonUpdate'], _batonDataJsonByViewer[_author]);
      expect(roomRepository.targetCalls, [
        (beaconId: _beaconId, messageId: _messageId, viewerUserId: _author),
      ]);
    });

    test('missing text or candidates is rejected by the schema', () async {
      for (final document in [
        '''
          mutation {
            roomBatonUpdate(
              batonId: "Lbaton000001"
              candidates: [{userId: "Ucandidate01", tier: 1}]
            )
          }
        ''',
        '''
          mutation {
            roomBatonUpdate(batonId: "Lbaton000001", text: "Ask")
          }
        ''',
      ]) {
        await expectLater(
          run(document, jwt: authorJwt),
          throwsA(isA<GraphQLException>()),
        );
      }
      expect(batonCase.updateCalls, isEmpty);
    });

    test('missing JWT is rejected without calling the case', () async {
      await expectLater(
        run(updateDocument, variables: variables),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(batonCase.updateCalls, isEmpty);
    });

    test(
      'case exceptions surface with their own codes, no read-back',
      () async {
        for (final (error, matcher) in <(Object, Matcher)>[
          (
            const BatonNotAuthorException(),
            failsWith<BatonNotAuthorException>(1323),
          ),
          (
            const BatonNotCollectingException(),
            failsWith<BatonNotCollectingException>(1325),
          ),
          (
            const BatonNotFoundException(),
            failsWith<BatonNotFoundException>(1322),
          ),
          (
            const BatonInvalidCandidatesException(),
            failsWith<BatonInvalidCandidatesException>(1326),
          ),
          (
            const BatonMessageNotEligibleException(),
            failsWith<BatonMessageNotEligibleException>(1329),
          ),
          (
            const BeaconCreateException(description: 'read-only'),
            throwsA(isA<BeaconCreateException>()),
          ),
        ]) {
          batonCase.failWith = error as Exception;
          await expectLater(
            run(updateDocument, variables: variables, jwt: authorJwt),
            matcher,
            reason: '$error',
          );
        }
        expect(roomRepository.targetCalls, isEmpty);
      },
    );
  });

  group('roomBatonRespond', () {
    for (final canHelp in [true, false]) {
      test('forwards canHelp=$canHelp for the JWT subject', () async {
        await run(
          r'''
            mutation Respond($canHelp: Boolean!) {
              roomBatonRespond(batonId: "Lbaton000001", canHelp: $canHelp)
            }
          ''',
          variables: {'canHelp': canHelp},
          jwt: candidateJwt,
        );

        expect(batonCase.respondCalls, [
          (actorId: _candidate, batonId: _batonId, canHelp: canHelp),
        ]);
      });
    }

    test(
      'returns the candidate-view batonDataJson, not the author view',
      () async {
        final result = await run(
          '''
          mutation {
            roomBatonRespond(batonId: "Lbaton000001", canHelp: true)
          }
        ''',
          jwt: candidateJwt,
        );

        expect(result['roomBatonRespond'], _batonDataJsonByViewer[_candidate]);
        expect(roomRepository.targetCalls, [
          (
            beaconId: _beaconId,
            messageId: _messageId,
            viewerUserId: _candidate,
          ),
        ]);
      },
    );

    test('missing canHelp is rejected by the schema', () async {
      await expectLater(
        run(
          '''
            mutation {
              roomBatonRespond(batonId: "Lbaton000001")
            }
          ''',
          jwt: candidateJwt,
        ),
        throwsA(isA<GraphQLException>()),
      );
      expect(batonCase.respondCalls, isEmpty);
    });

    test('missing JWT is rejected without calling the case', () async {
      await expectLater(
        run('''
          mutation {
            roomBatonRespond(batonId: "Lbaton000001", canHelp: true)
          }
        '''),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(batonCase.respondCalls, isEmpty);
    });

    test('case exceptions surface with their own codes', () async {
      const document = '''
        mutation {
          roomBatonRespond(batonId: "Lbaton000001", canHelp: true)
        }
      ''';
      batonCase.failWith = const BatonNotCandidateException();
      await expectLater(
        run(document, jwt: candidateJwt),
        failsWith<BatonNotCandidateException>(1324),
      );
      batonCase.failWith = const BatonNotCollectingException();
      await expectLater(
        run(document, jwt: candidateJwt),
        failsWith<BatonNotCollectingException>(1325),
      );
    });
  });

  group('roomBatonSelect', () {
    test('a chosen userId is forwarded as a manual pick', () async {
      await run(
        '''
          mutation {
            roomBatonSelect(batonId: "Lbaton000001", userId: "Ucandidate01")
          }
        ''',
        jwt: authorJwt,
      );

      expect(batonCase.selectCalls, [
        (actorId: _author, batonId: _batonId, userId: 'Ucandidate01'),
      ]);
    });

    test('an omitted userId asks the case to pick automatically', () async {
      await run(
        '''
          mutation {
            roomBatonSelect(batonId: "Lbaton000001")
          }
        ''',
        jwt: authorJwt,
      );

      expect(batonCase.selectCalls, [
        (actorId: _author, batonId: _batonId, userId: null),
      ]);
    });

    test(
      'an explicit null userId asks the case to pick automatically',
      () async {
        await run(
          r'''
          mutation Select($userId: String) {
            roomBatonSelect(batonId: "Lbaton000001", userId: $userId)
          }
        ''',
          variables: const {'userId': null},
          jwt: authorJwt,
        );

        expect(batonCase.selectCalls, [
          (actorId: _author, batonId: _batonId, userId: null),
        ]);
      },
    );

    test('returns the author-view batonDataJson after selecting', () async {
      final result = await run(
        '''
          mutation {
            roomBatonSelect(batonId: "Lbaton000001")
          }
        ''',
        jwt: authorJwt,
      );

      expect(result['roomBatonSelect'], _batonDataJsonByViewer[_author]);
      expect(roomRepository.targetCalls, [
        (beaconId: _beaconId, messageId: _messageId, viewerUserId: _author),
      ]);
    });

    test('missing JWT is rejected without calling the case', () async {
      await expectLater(
        run('''
          mutation {
            roomBatonSelect(batonId: "Lbaton000001")
          }
        '''),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(batonCase.selectCalls, isEmpty);
    });

    test('case exceptions surface with their own codes', () async {
      const document = '''
        mutation {
          roomBatonSelect(batonId: "Lbaton000001")
        }
      ''';
      batonCase.failWith = const BatonNotAuthorException();
      await expectLater(
        run(document, jwt: authorJwt),
        failsWith<BatonNotAuthorException>(1323),
      );
      batonCase.failWith = const BatonTakerNotAvailableException();
      await expectLater(
        run(document, jwt: authorJwt),
        failsWith<BatonTakerNotAvailableException>(1328),
      );
    });
  });

  group('roomBatonCancel', () {
    test('cancels as the JWT subject and returns true', () async {
      final result = await run(
        '''
          mutation {
            roomBatonCancel(batonId: "Lbaton000001")
          }
        ''',
        jwt: authorJwt,
      );

      expect(result['roomBatonCancel'], isTrue);
      expect(batonCase.cancelCalls, [
        (actorId: _author, batonId: _batonId),
      ]);
    });

    test('missing JWT is rejected without calling the case', () async {
      await expectLater(
        run('''
          mutation {
            roomBatonCancel(batonId: "Lbaton000001")
          }
        '''),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(batonCase.cancelCalls, isEmpty);
    });

    test('case exceptions surface with their own codes', () async {
      batonCase.failWith = const BatonNotFoundException();
      await expectLater(
        run('''
          mutation {
            roomBatonCancel(batonId: "Lbaton000001")
          }
        ''', jwt: authorJwt),
        failsWith<BatonNotFoundException>(1322),
      );
    });
  });
}
