import 'package:get_it/get_it.dart';
import 'package:graphql_schema2/graphql_schema2.dart';

import 'package:tentura_server/domain/use_case/beacon_room_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// U088 — the author bans someone from the Request lobby, or lets them back.
final class MutationBeaconLobby extends GqlNodeBase {
  MutationBeaconLobby({BeaconRoomCase? beaconRoomCase})
    : _case = beaconRoomCase ?? GetIt.I<BeaconRoomCase>();

  final BeaconRoomCase _case;

  final _beaconIdStr = InputFieldString(fieldName: 'beaconId');

  final _userIdStr = InputFieldString(fieldName: 'userId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [ban, unban];

  GraphQLObjectField<dynamic, dynamic> get ban => GraphQLObjectField(
    'BeaconLobbyBan',
    graphQLBoolean.nonNullable(),
    arguments: [_beaconIdStr.field, _userIdStr.field],
    resolve: (_, args) => _case.banFromLobby(
      beaconId: _beaconIdStr.fromArgsNonNullable(args),
      userId: getCredentials(args).sub,
      bannedUserId: _userIdStr.fromArgsNonNullable(args),
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get unban => GraphQLObjectField(
    'BeaconLobbyUnban',
    graphQLBoolean.nonNullable(),
    arguments: [_beaconIdStr.field, _userIdStr.field],
    resolve: (_, args) => _case.unbanFromLobby(
      beaconId: _beaconIdStr.fromArgsNonNullable(args),
      userId: getCredentials(args).sub,
      bannedUserId: _userIdStr.fromArgsNonNullable(args),
    ),
  );
}
