import 'package:tentura_server/domain/use_case/beacon_help_offerer_forward_path_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Root query field [beaconHelpOffererForwardPath]: edge set delivering the
/// beacon to a single active help offerer (the focus user) plus the viewer's
/// own sub-chain so case 2 ("involved-other" viewers) sees how they fit
/// between the author and the help offerer.
///
/// See [BeaconHelpOffererForwardPathCase] for the auth model and the SQL
/// recursive-CTE seed predicate.
final class QueryHelpOffererForwardPath extends GqlNodeBase {
  QueryHelpOffererForwardPath({
    BeaconHelpOffererForwardPathCase? beaconHelpOffererForwardPathCase,
  }) : _beaconHelpOffererForwardPathCase =
            beaconHelpOffererForwardPathCase ??
                GetIt.I<BeaconHelpOffererForwardPathCase>();

  final BeaconHelpOffererForwardPathCase _beaconHelpOffererForwardPathCase;

  static final _helpOffererId =
      InputFieldString(fieldName: 'helpOffererId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconHelpOffererForwardPath,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconHelpOffererForwardPath =>
      GraphQLObjectField(
        'beaconHelpOffererForwardPath',
        gqlTypeForwardGraphResult.nonNullable(),
        arguments: [InputFieldId.field, _helpOffererId.field],
        resolve: (_, args) {
          final creds = getCredentials(args);
          return _beaconHelpOffererForwardPathCase.asMap(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            helpOffererId: _helpOffererId.fromArgsNonNullable(args),
            currentUserId: creds.sub,
          );
        },
      );
}
