import 'package:tentura_server/domain/use_case/beacon_member_webs_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/constellation_gql_maps.dart';

/// Root query field [beaconMemberWebs]: member web of one Request.
final class QueryBeaconMemberWebs extends GqlNodeBase {
  QueryBeaconMemberWebs({BeaconMemberWebsCase? beaconMemberWebsCase})
    : _case = beaconMemberWebsCase ?? GetIt.I<BeaconMemberWebsCase>();

  final BeaconMemberWebsCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [beaconMemberWebs];

  GraphQLObjectField<dynamic, dynamic> get beaconMemberWebs =>
      GraphQLObjectField(
        'beaconMemberWebs',
        GraphQLListType(gqlTypeConstellationMemberWeb.nonNullable())
            .nonNullable(),
        arguments: [InputFieldId.field],
        resolve: (_, args) async => [
          for (final web in await _case.memberWebs(
            beaconId: InputFieldId.fromArgsNonNullable(args),
            viewerId: getCredentials(args).sub,
          ))
            constellationMemberWebToGqlMap(web),
        ],
      );
}
