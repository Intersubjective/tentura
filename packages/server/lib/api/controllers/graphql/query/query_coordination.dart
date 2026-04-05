import 'package:tentura_server/domain/use_case/coordination_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryCoordination extends GqlNodeBase {
  QueryCoordination({CoordinationCase? coordinationCase})
    : _coordinationCase = coordinationCase ?? GetIt.I<CoordinationCase>();

  final CoordinationCase _coordinationCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    commitmentsWithCoordination,
  ];

  GraphQLObjectField<dynamic, dynamic> get commitmentsWithCoordination =>
      GraphQLObjectField(
        'commitmentsWithCoordination',
        GraphQLListType(gqlTypeCommitmentWithCoordinationRow.nonNullable()),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          getCredentials(args);
          return _coordinationCase.commitmentsWithCoordination(
            beaconId: InputFieldId.fromArgsNonNullable(args),
          );
        },
      );
}
