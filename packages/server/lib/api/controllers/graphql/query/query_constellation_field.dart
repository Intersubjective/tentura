import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
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

  final GraphQLFieldInput<bool, bool> _showClosed = GraphQLFieldInput(
    'showClosed',
    graphQLBoolean.nonNullable(),
    defaultValue: false,
  );

  final GraphQLFieldInput<bool, bool> _participatedOnly = GraphQLFieldInput(
    'participatedOnly',
    graphQLBoolean.nonNullable(),
    defaultValue: false,
  );

  final GraphQLFieldInput<String, String> _projection = GraphQLFieldInput(
    'projection',
    gqlEnumConstellationProjection.nonNullable(),
    defaultValue: 'FULL',
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [constellationField];

  GraphQLObjectField<dynamic, dynamic> get constellationField =>
      GraphQLObjectField(
        'constellationField',
        gqlTypeConstellationField.nonNullable(),
        arguments: [
          _showClosed,
          _participatedOnly,
          _projection,
        ],
        resolve: (_, args) {
          final viewerId = getCredentials(args).sub;
          final projectionWire = args[_projection.name]! as String;
          final projection =
              ConstellationProjection.fromWire(projectionWire) ??
              ConstellationProjection.full;
          return _constellationFieldCase
              .readSnapshot(
                viewerId: viewerId,
                context: kConstellationContext,
                params: (
                  filters: ConstellationFieldMembershipFilters(
                    showClosed: args[_showClosed.name]! as bool,
                    participatedOnly: args[_participatedOnly.name]! as bool,
                  ),
                  projection: projection,
                ),
              )
              .then(constellationFieldToGqlMap);
        },
      );
}
