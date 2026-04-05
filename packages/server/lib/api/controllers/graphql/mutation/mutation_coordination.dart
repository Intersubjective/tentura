import 'package:tentura_server/domain/use_case/coordination_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationCoordination extends GqlNodeBase {
  MutationCoordination({CoordinationCase? coordinationCase})
    : _coordinationCase = coordinationCase ?? GetIt.I<CoordinationCase>();

  final CoordinationCase _coordinationCase;

  final _commitUserId = InputFieldString(fieldName: 'commitUserId');

  final GraphQLFieldInput<int, int> _responseTypeField = GraphQLFieldInput(
    'responseType',
    graphQLInt.nonNullable(),
  );

  final GraphQLFieldInput<int, int> _coordinationStatusField = GraphQLFieldInput(
    'coordinationStatus',
    graphQLInt.nonNullable(),
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    setCoordinationResponse,
    setBeaconCoordinationStatus,
  ];

  GraphQLObjectField<dynamic, dynamic> get setCoordinationResponse =>
      GraphQLObjectField(
        'setCoordinationResponse',
        gqlTypeCoordinationStatusResult.nonNullable(),
        arguments: [
          InputFieldId.field,
          _commitUserId.field,
          _responseTypeField,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _coordinationCase.setCoordinationResponse(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            commitUserId: _commitUserId.fromArgsNonNullable(args),
            authorUserId: jwt.sub,
            responseType: args[_responseTypeField.name]! as int,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get setBeaconCoordinationStatus =>
      GraphQLObjectField(
        'setBeaconCoordinationStatus',
        graphQLBoolean.nonNullable(),
        arguments: [
          InputFieldId.field,
          _coordinationStatusField,
        ],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _coordinationCase.setBeaconCoordinationStatus(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            authorUserId: jwt.sub,
            status: args[_coordinationStatusField.name]! as int,
          );
        },
      );
}
