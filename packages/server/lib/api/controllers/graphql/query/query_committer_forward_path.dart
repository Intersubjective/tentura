import 'package:tentura_server/domain/use_case/beacon_committer_forward_path_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Root query field [beaconCommitterForwardPath]: edge set delivering the
/// beacon to a single active committer (the focus user) plus the viewer's
/// own sub-chain so case 2 ("involved-other" viewers) sees how they fit
/// between the author and the committer.
///
/// See [BeaconCommitterForwardPathCase] for the auth model and the SQL
/// recursive-CTE seed predicate.
final class QueryCommitterForwardPath extends GqlNodeBase {
  QueryCommitterForwardPath({
    BeaconCommitterForwardPathCase? beaconCommitterForwardPathCase,
  }) : _beaconCommitterForwardPathCase =
            beaconCommitterForwardPathCase ??
                GetIt.I<BeaconCommitterForwardPathCase>();

  final BeaconCommitterForwardPathCase _beaconCommitterForwardPathCase;

  static final _committerId =
      InputFieldString(fieldName: 'committerId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconCommitterForwardPath,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconCommitterForwardPath =>
      GraphQLObjectField(
        'beaconCommitterForwardPath',
        gqlTypeForwardGraphResult.nonNullable(),
        arguments: [InputFieldId.field, _committerId.field],
        resolve: (_, args) {
          final creds = getCredentials(args);
          return _beaconCommitterForwardPathCase.asMap(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            committerId: _committerId.fromArgsNonNullable(args),
            currentUserId: creds.sub,
          );
        },
      );
}
