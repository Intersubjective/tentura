import 'package:tentura_server/domain/use_case/beacon_display_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/beacon_display_gql_maps.dart';

final class QueryBeaconDisplay extends GqlNodeBase {
  QueryBeaconDisplay({BeaconDisplayCase? beaconDisplayCase})
    : _beaconDisplayCase =
          beaconDisplayCase ?? GetIt.I<BeaconDisplayCase>();

  final BeaconDisplayCase _beaconDisplayCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [beaconDisplayStatuses];

  GraphQLObjectField<dynamic, dynamic> get beaconDisplayStatuses =>
      GraphQLObjectField(
        'beaconDisplayStatuses',
        GraphQLListType(gqlTypeBeaconDisplayStatus.nonNullable()),
        arguments: [InputFieldBeaconIds.field],
        resolve: (_, args) {
          final jwt = getCredentials(args);
          return _beaconDisplayCase
              .displayStatuses(
                beaconIds: InputFieldBeaconIds.fromArgs(args),
                viewerId: jwt.sub,
              )
              .then(
                (rows) => rows.map(beaconDisplayStatusToGqlMap).toList(),
              );
        },
      );
}
