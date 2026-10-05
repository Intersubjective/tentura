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
      <({
        String actorId,
        String messageId,
        List<({String userId, int tier})> candidates,
      })>[];
  final respondCalls =
      <({String actorId, String batonId, bool canHelp})>[];
  final selectCalls =
      <({String actorId, String batonId, String? userId})>[];
  final cancelCalls = <({String actorId, String batonId})>[];

  Object? failWith;

  @override
  Future<RoomBaton> create({
    required String actorId,
    required String messageId,
    required List<({String userId, int tier})> candidates,
  }) async {
    createCalls.add((
      actorId: actorId,
      messageId: messageId,
      candidates: candidates,
    ));
    if (failWith case final Object e) throw e;
    return RoomBaton(
      id: _batonId,
      messageId: messageId,
      beaconId: _beaconId,
      authorId: actorId,
      status: BatonStatus.collecting,
      createdAt: DateTime.utc(2026, 10, 5),
    );
  }

  @override
  Future<void> respond({
    required String actorId,
    required String batonId,
    required bool canHelp,
  }) async {
    respondCalls.add((actorId: actorId, batonId: batonId, canHelp: canHelp));
    if (failWith case final Object e) throw e;
  }

  @override
  Future<void> select({
    required String actorId,
    required String batonId,
    String? userId,
  }) async {
    selectCalls.add((actorId: actorId, batonId: batonId, userId: userId));
    if (failWith case final Object e) throw e;
  }

  @override
  Future<void> cancel({
    required String actorId,
    required String batonId,
  }) async {
    cancelCalls.add((actorId: actorId, batonId: batonId));
    if (failWith case final Object e) throw e;
  }
}

const _beaconId = 'Bbeacon000001';
const _messageId = 'Mmessage00001';
const _batonId = 'Lbaton000001';
const _author = 'Ubaton-author';
const _candidate = 'Ubaton-candidate';
const _bystander = 'Ubaton-bystander';

/// What the room read path (`batonDataJson`, per viewer) yields for the baton
/// on [_messageId]; the author sees the full list, a candidate only their own
/// answer, and a bystander nothing.
const _batonDataJsonByViewer = <String, String?>{
  _author:
      '{"id":"$_batonId","status":"collecting","viewerRole":"author",'
      '"candidates":[{"userId":"$_candidate","tier":1,"response":"waiting"}]}',
  _candidate:
      '{"id":"$_batonId","status":"collecting","viewerRole":"candidate",'
      '"myResponse":"waiting"}',
  _bystander: null,
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
    test('exposes the four baton mutations', () {
      expect(
        mutation.all.map((f) => f.name).toSet(),
        {
          'roomBatonCreate',
          'roomBatonRespond',
          'roomBatonSelect',
          'roomBatonCancel',
        },
      );
    });

    test('roomBatonCreate takes a non-null list of candidate inputs', () {
      final create = mutation.all.singleWhere(
        (f) => f.name == 'roomBatonCreate',
      );
      final candidates = create.inputs.singleWhere(
        (i) => i.name == 'candidates',
      );
      expect(candidates.type, isA<GraphQLNonNullableType<dynamic, dynamic>>());
      expect(_baseTypeName(candidates.type), 'RoomBatonCandidateInput');
      expect(
        create.inputs.singleWhere((i) => i.name == 'messageId').type,
        isA<GraphQLNonNullableType<dynamic, dynamic>>(),
      );
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
    test('uses the JWT subject as actor and maps message and candidates',
        () async {
      await run(
        r'''
          mutation Create($messageId: String!, $candidates: [RoomBatonCandidateInput!]!) {
            roomBatonCreate(messageId: $messageId, candidates: $candidates)
          }
        ''',
        variables: const {
          'messageId': _messageId,
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
      expect(call.messageId, _messageId);
      expect(call.candidates, [
        (userId: 'Ucandidate01', tier: 1),
        (userId: 'Ucandidate02', tier: 3),
      ]);
    });

    test('returns the author-view batonDataJson read for the new baton',
        () async {
      final result = await run(
        r'''
          mutation {
            roomBatonCreate(
              messageId: "Mmessage00001"
              candidates: [{userId: "Ubaton-candidate", tier: 1}]
            )
          }
        ''',
        jwt: authorJwt,
      );

      expect(result['roomBatonCreate'], _batonDataJsonByViewer[_author]);
      expect(roomRepository.targetCalls, [
        (beaconId: _beaconId, messageId: _messageId, viewerUserId: _author),
      ]);
    });

    test('rejects a candidate without a tier before reaching the case',
        () async {
      await expectLater(
        run(
          r'''
            mutation Create($candidates: [RoomBatonCandidateInput!]!) {
              roomBatonCreate(messageId: "Mmessage00001", candidates: $candidates)
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
    });

    test('missing JWT is rejected without calling the case', () async {
      await expectLater(
        run(r'''
          mutation {
            roomBatonCreate(
              messageId: "Mmessage00001"
              candidates: [{userId: "Ucandidate01", tier: 1}]
            )
          }
        '''),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(batonCase.createCalls, isEmpty);
    });

    test('case exceptions surface with their own codes', () async {
      const document = r'''
        mutation {
          roomBatonCreate(
            messageId: "Mmessage00001"
            candidates: [{userId: "Ucandidate01", tier: 1}]
          )
        }
      ''';
      batonCase.failWith = const BatonInvalidCandidatesException();
      await expectLater(
        run(document, jwt: authorJwt),
        failsWith<BatonInvalidCandidatesException>(1326),
      );
      batonCase.failWith = const BatonAlreadyActiveException();
      await expectLater(
        run(document, jwt: authorJwt),
        failsWith<BatonAlreadyActiveException>(1327),
      );
      batonCase.failWith = const BatonMessageNotEligibleException();
      await expectLater(
        run(document, jwt: authorJwt),
        failsWith<BatonMessageNotEligibleException>(1329),
      );
    });
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

    test('returns the candidate-view batonDataJson, not the author view',
        () async {
      final result = await run(
        r'''
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
    });

    test('missing canHelp is rejected by the schema', () async {
      await expectLater(
        run(
          r'''
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
        run(r'''
          mutation {
            roomBatonRespond(batonId: "Lbaton000001", canHelp: true)
          }
        '''),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(batonCase.respondCalls, isEmpty);
    });

    test('case exceptions surface with their own codes', () async {
      const document = r'''
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
        r'''
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
        r'''
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

    test('an explicit null userId asks the case to pick automatically',
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
    });

    test('returns the author-view batonDataJson after selecting', () async {
      final result = await run(
        r'''
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
        run(r'''
          mutation {
            roomBatonSelect(batonId: "Lbaton000001")
          }
        '''),
        throwsA(isA<UnauthorizedException>()),
      );
      expect(batonCase.selectCalls, isEmpty);
    });

    test('case exceptions surface with their own codes', () async {
      const document = r'''
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
        r'''
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
        run(r'''
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
        run(r'''
          mutation {
            roomBatonCancel(batonId: "Lbaton000001")
          }
        ''', jwt: authorJwt),
        failsWith<BatonNotFoundException>(1322),
      );
    });
  });
}
