import 'package:tentura_server/domain/use_case/beacon_room_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryBeaconRoom extends GqlNodeBase {
  QueryBeaconRoom({BeaconRoomCase? beaconRoomCase})
      : _case = beaconRoomCase ?? GetIt.I<BeaconRoomCase>();

  final BeaconRoomCase _case;

  final _beaconIdStr = InputFieldString(fieldName: 'beaconId');

  final _beforeIso = InputFieldString(fieldName: 'beforeIso');

  List<GraphQLObjectField<dynamic, dynamic>> get all =>
      [
        roomMessageList,
        beaconParticipantList,
        beaconRoomStateGet,
        beaconActivityEventList,
        inboxRoomContextBatch,
      ];

  GraphQLObjectField<dynamic, dynamic> get roomMessageList =>
      GraphQLObjectField(
        'RoomMessageList',
        GraphQLListType(gqlTypeRoomMessageRow.nonNullable()).nonNullable(),
        arguments: [
          _beaconIdStr.field,
          _beforeIso.fieldNullable,
        ],
        resolve: (_, args) => _case.listMessages(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          beforeIso: _beforeIso.fromArgs(args),
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconParticipantList =>
      GraphQLObjectField(
        'BeaconParticipantList',
        GraphQLListType(gqlTypeBeaconParticipantRow.nonNullable()).nonNullable(),
        arguments: [
          _beaconIdStr.field,
        ],
        resolve: (_, args) => _case.listParticipants(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconRoomStateGet =>
      GraphQLObjectField(
        'BeaconRoomStateGet',
        gqlTypeBeaconRoomStateRow.nonNullable(),
        arguments: [
          _beaconIdStr.field,
        ],
        resolve: (_, args) => _case.beaconRoomStateGet(
              beaconId: _beaconIdStr.fromArgsNonNullable(args),
              userId: getCredentials(args).sub,
            ),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconActivityEventList =>
      GraphQLObjectField(
        'BeaconActivityEventList',
        GraphQLListType(gqlTypeBeaconActivityEventRow.nonNullable()).nonNullable(),
        arguments: [
          _beaconIdStr.field,
        ],
        resolve: (_, args) => _case.listActivityEvents(
          beaconId: _beaconIdStr.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
        ),
      );

  GraphQLObjectField<dynamic, dynamic> get inboxRoomContextBatch =>
      GraphQLObjectField(
        'InboxRoomContextBatch',
        GraphQLListType(gqlTypeInboxRoomContextRow.nonNullable()).nonNullable(),
        arguments: [InputFieldBeaconIds.field],
        resolve: (_, args) => _case.inboxRoomContextBatch(
              userId: getCredentials(args).sub,
              beaconIds: InputFieldBeaconIds.fromArgs(args),
            ),
      );
}
