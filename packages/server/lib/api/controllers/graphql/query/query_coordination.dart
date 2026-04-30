import 'package:tentura_server/domain/use_case/coordination_case.dart';

import '../custom_types.dart';
import '../mappers/gql_public_user_maps.dart';
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
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final rows = await _coordinationCase.commitmentsWithCoordination(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            viewerId: jwt.sub,
          );
          return rows.map(commitmentWithCoordinationToGqlMap).toList();
        },
      );
}
