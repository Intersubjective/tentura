import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/use_case/constellation_field_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../mappers/constellation_gql_maps.dart';

/// Root query field [constellationField]: peers, trust edges, and requests for
/// the JWT viewer. MeritRank context is pinned server-side (D14 / A2).
final class QueryConstellationField extends GqlNodeBase {
  QueryConstellationField({ConstellationFieldCase? constellationFieldCase})
    : _constellationFieldCase =
          constellationFieldCase ?? GetIt.I<ConstellationFieldCase>();

  final ConstellationFieldCase _constellationFieldCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [constellationField];

  GraphQLObjectField<dynamic, dynamic> get constellationField =>
      GraphQLObjectField(
        'constellationField',
        gqlTypeConstellationField.nonNullable(),
        resolve: (_, args) => _constellationFieldCase
            .load(
              viewerId: getCredentials(args).sub,
              context: kConstellationContext,
            )
            .then(constellationFieldToGqlMap),
      );
}
