import 'package:get_it/get_it.dart';
import 'package:graphql_schema2/graphql_schema2.dart';

import 'package:tentura_server/domain/use_case/beacon_room_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// U088 — the Request lobby: a discussion for the people who offered help and
/// the author. Its messages use the item-thread arguments that already exist
/// on `RoomMessageList` / `RoomMessageCreate` / `MarkThreadSeen`
/// (`threadItemId` = the `lobbyId` returned here).
final class QueryBeaconLobby extends GqlNodeBase {
  QueryBeaconLobby({BeaconRoomCase? beaconRoomCase})
    : _case = beaconRoomCase ?? GetIt.I<BeaconRoomCase>();

  final BeaconRoomCase _case;

  final _beaconIdStr = InputFieldString(fieldName: 'beaconId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [beaconLobby];

  GraphQLObjectField<dynamic, dynamic> get beaconLobby => GraphQLObjectField(
    'BeaconLobby',
    gqlTypeBeaconLobby.nonNullable(),
    arguments: [_beaconIdStr.field],
    resolve: (_, args) => _case.beaconLobby(
      beaconId: _beaconIdStr.fromArgsNonNullable(args),
      userId: getCredentials(args).sub,
    ),
  );
}
