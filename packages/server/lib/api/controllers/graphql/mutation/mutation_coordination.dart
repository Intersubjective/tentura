import 'package:tentura_server/domain/use_case/coordination_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/beacon_display_gql_maps.dart';

final class MutationCoordination extends GqlNodeBase {
  MutationCoordination({CoordinationCase? coordinationCase})
    : _coordinationCase = coordinationCase ?? GetIt.I<CoordinationCase>();

  final CoordinationCase _coordinationCase;

  final _offerUserId = InputFieldString(fieldName: 'offerUserId');
  final _reason = InputFieldString(fieldName: 'reason');

  final GraphQLFieldInput<int, int> _responseTypeField = GraphQLFieldInput(
    'responseType',
    graphQLInt.nonNullable(),
  );

  final GraphQLFieldInput<bool, bool> _inviteToRoomField = GraphQLFieldInput(
    'inviteToRoom',
    graphQLBoolean.nonNullable(),
    defaultValue: false,
  );

  final GraphQLFieldInput<bool, bool> _removeFromRoomField = GraphQLFieldInput(
    'removeFromRoom',
    graphQLBoolean.nonNullable(),
    defaultValue: false,
  );

  final GraphQLFieldInput<int, int> _statusField = GraphQLFieldInput(
    'status',
    graphQLInt.nonNullable(),
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    setCoordinationResponse,
    acceptHelpOffer,
    declineHelpOffer,
    removeFromRoom,
    setBeaconStatus,
  ];

  GraphQLObjectField<dynamic, dynamic> get setCoordinationResponse =>
      GraphQLObjectField(
        'setCoordinationResponse',
        gqlTypeBeaconStatusResult.nonNullable(),
        arguments: [
          InputFieldId.field,
          _offerUserId.field,
          _responseTypeField,
          _inviteToRoomField,
          _removeFromRoomField,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _coordinationCase
              .setCoordinationResponse(
                beaconId: InputFieldId.fromArgsNonNullable(args),
                offerUserId: _offerUserId.fromArgsNonNullable(args),
                authorUserId: jwt.sub,
                responseType: args[_responseTypeField.name]! as int,
                inviteToRoom: args[_inviteToRoomField.name]! as bool,
                removeFromRoom: args[_removeFromRoomField.name]! as bool,
              )
              .then(beaconStatusResultToGqlMap);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get acceptHelpOffer =>
      GraphQLObjectField(
        'acceptHelpOffer',
        gqlTypeBeaconStatusResult.nonNullable(),
        arguments: [
          InputFieldId.field,
          _offerUserId.field,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _coordinationCase
              .acceptHelpOffer(
                beaconId: InputFieldId.fromArgsNonNullable(args),
                offerUserId: _offerUserId.fromArgsNonNullable(args),
                actorUserId: jwt.sub,
              )
              .then(beaconStatusResultToGqlMap);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get declineHelpOffer =>
      GraphQLObjectField(
        'declineHelpOffer',
        gqlTypeBeaconStatusResult.nonNullable(),
        arguments: [
          InputFieldId.field,
          _offerUserId.field,
          _reason.field,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _coordinationCase
              .declineHelpOffer(
                beaconId: InputFieldId.fromArgsNonNullable(args),
                offerUserId: _offerUserId.fromArgsNonNullable(args),
                actorUserId: jwt.sub,
                reason: _reason.fromArgsNonNullable(args),
              )
              .then(beaconStatusResultToGqlMap);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get removeFromRoom => GraphQLObjectField(
    'removeFromRoom',
    gqlTypeBeaconStatusResult.nonNullable(),
    arguments: [
      InputFieldId.field,
      _offerUserId.field,
      _reason.field,
    ],
    resolve: (_, args) {
      final jwt = getCredentials(args);
      return _coordinationCase
          .removeFromRoom(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            offerUserId: _offerUserId.fromArgsNonNullable(args),
            actorUserId: jwt.sub,
            reason: _reason.fromArgsNonNullable(args),
          )
          .then(beaconStatusResultToGqlMap);
    },
  );

  GraphQLObjectField<dynamic, dynamic> get setBeaconStatus =>
      GraphQLObjectField(
        'setBeaconStatus',
        gqlTypeBeaconStatusResult.nonNullable(),
        arguments: [
          InputFieldId.field,
          _statusField,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _coordinationCase
              .setBeaconStatus(
                beaconId: InputFieldId.fromArgsNonNullable(args),
                authorUserId: jwt.sub,
                status: args[_statusField.name]! as int,
              )
              .then(beaconStatusResultToGqlMap);
        },
      );
}
