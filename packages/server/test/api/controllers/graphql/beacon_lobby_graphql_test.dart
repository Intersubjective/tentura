import 'package:graphql_schema2/graphql_schema2.dart';
import 'package:graphql_server2/graphql_server2.dart';
import 'package:mockito/mockito.dart' show Fake;
import 'package:test/test.dart';

import 'package:tentura_server/api/controllers/graphql/custom_types.dart';
import 'package:tentura_server/api/controllers/graphql/input/_input_types.dart';
import 'package:tentura_server/api/controllers/graphql/mutation/mutation_beacon_lobby.dart';
import 'package:tentura_server/api/controllers/graphql/query/query_beacon_lobby.dart';
import 'package:tentura_server/domain/entity/jwt_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/use_case/beacon_room_case.dart';

/// Records what the GraphQL layer forwards to the lobby use case (U088).
final class _RecordingLobbyCase extends Fake implements BeaconRoomCase {
  final calls = <String>[];

  @override
  Future<Map<String, Object?>> beaconLobby({
    required String beaconId,
    required String userId,
  }) async {
    calls.add('open $beaconId $userId');
    return {
      'beaconId': beaconId,
      'lobbyId': 'Llobby1',
      'isAuthor': true,
      'canPost': true,
      'bannedUserIds': ['Unina'],
    };
  }

  @override
  Future<bool> banFromLobby({
    required String beaconId,
    required String userId,
    required String bannedUserId,
  }) async {
    calls.add('ban $beaconId $userId $bannedUserId');
    return true;
  }

  @override
  Future<bool> unbanFromLobby({
    required String beaconId,
    required String userId,
    required String bannedUserId,
  }) async {
    calls.add('unban $beaconId $userId $bannedUserId');
    return true;
  }
}

void main() {
  const jwt = JwtEntity(sub: 'Uauthor');
  late _RecordingLobbyCase lobbyCase;
  late GraphQL graphQL;

  setUp(() {
    lobbyCase = _RecordingLobbyCase();
    graphQL = GraphQL(
      GraphQLSchema(
        queryType: GraphQLObjectType('Query', 'Query root')
          ..fields.addAll(QueryBeaconLobby(beaconRoomCase: lobbyCase).all),
        mutationType: GraphQLObjectType('Mutation', 'Mutation root')
          ..fields.addAll(MutationBeaconLobby(beaconRoomCase: lobbyCase).all),
      ),
    );
  });

  Future<Map<String, dynamic>> run(String doc) async =>
      await graphQL.parseAndExecute(
            doc,
            globalVariables: {kGlobalInputQueryJwt: jwt},
          )
          as Map<String, dynamic>;

  test('BeaconLobby opens the lobby for the caller', () async {
    final data = await run(
      'query { BeaconLobby(beaconId: "B1") '
      '{ beaconId lobbyId isAuthor canPost bannedUserIds } }',
    );
    expect(data['BeaconLobby'], {
      'beaconId': 'B1',
      'lobbyId': 'Llobby1',
      'isAuthor': true,
      'canPost': true,
      'bannedUserIds': ['Unina'],
    });
    expect(lobbyCase.calls, ['open B1 Uauthor']);
  });

  test(
    'BeaconLobbyBan / BeaconLobbyUnban forward the caller as author',
    () async {
      final ban = await run(
        'mutation { BeaconLobbyBan(beaconId: "B1", userId: "Unina") }',
      );
      final unban = await run(
        'mutation { BeaconLobbyUnban(beaconId: "B1", userId: "Unina") }',
      );
      expect(ban['BeaconLobbyBan'], isTrue);
      expect(unban['BeaconLobbyUnban'], isTrue);
      expect(lobbyCase.calls, [
        'ban B1 Uauthor Unina',
        'unban B1 Uauthor Unina',
      ]);
    },
  );

  test('bannedUserIds is a list type without an outer non-null wrapper', () {
    final type = gqlTypeBeaconLobby.fields
        .firstWhere((f) => f.name == 'bannedUserIds')
        .type;
    expect(type, isA<GraphQLListType<Object?, Object?>>());
    expect(
      (type as GraphQLListType<Object?, Object?>).ofType,
      isA<GraphQLNonNullableType<Object?, Object?>>(),
    );
  });

  test('lobby access denial has its own code (client maps 1347)', () {
    expect(const BeaconLobbyAccessException().code.codeNumber, 1347);
  });
}
