import 'package:tentura_server/domain/use_case/beacon_forward_graph_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Root query field [beaconForwardGraph]: edges visible to the viewer plus the
/// ancestor closure and the chain that delivered the beacon to each active
/// committer. See [BeaconForwardGraphCase] for the visibility model.
final class QueryForwardGraph extends GqlNodeBase {
  QueryForwardGraph({BeaconForwardGraphCase? beaconForwardGraphCase})
    : _beaconForwardGraphCase =
          beaconForwardGraphCase ?? GetIt.I<BeaconForwardGraphCase>();

  final BeaconForwardGraphCase _beaconForwardGraphCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [beaconForwardGraph];

  GraphQLObjectField<dynamic, dynamic> get beaconForwardGraph =>
      GraphQLObjectField(
        'beaconForwardGraph',
        gqlTypeForwardGraphResult.nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) {
          final creds = getCredentials(args);
          return _beaconForwardGraphCase.asMap(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            currentUserId: creds.sub,
          );
        },
      );
}
