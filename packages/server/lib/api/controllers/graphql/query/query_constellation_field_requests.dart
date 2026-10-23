import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/entity/constellation_anchor_projection.dart';
import 'package:tentura_server/domain/use_case/constellation_field_requests_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../mappers/constellation_gql_maps.dart';

/// Root query field [constellationFieldRequests] (#671): the few Requests a
/// `constellation_item` hint named, each only if the JWT viewer may read and
/// discover it. The hint itself carries no content.
final class QueryConstellationFieldRequests extends GqlNodeBase {
  QueryConstellationFieldRequests({ConstellationFieldRequestsCase? case_})
    : _case = case_ ?? GetIt.I<ConstellationFieldRequestsCase>();

  final ConstellationFieldRequestsCase _case;

  final GraphQLFieldInput<List<String>, List<String>> _ids = GraphQLFieldInput(
    'ids',
    GraphQLListType(graphQLString.nonNullable()).nonNullable(),
  );

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

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationFieldRequests,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationFieldRequests =>
      GraphQLObjectField(
        'constellationFieldRequests',
        GraphQLListType(
          gqlTypeConstellationRequest.nonNullable(),
        ).nonNullable(),
        arguments: [_ids, _showClosed, _participatedOnly],
        resolve: (_, args) {
          final viewerId = getCredentials(args).sub;
          final ids = {
            for (final id in List<String>.from(args[_ids.name]! as List))
              if (id.trim().isNotEmpty) id,
          };
          if (ids.length > kConstellationFieldRequestsByIdsCap) {
            throw ArgumentError.value(
              ids.length,
              'ids',
              'at most $kConstellationFieldRequestsByIdsCap',
            );
          }
          return _case
              .discoverableRequestsByIds(
                viewerId: viewerId,
                beaconIds: ids,
                filters: ConstellationFieldMembershipFilters(
                  showClosed: args[_showClosed.name]! as bool,
                  participatedOnly: args[_participatedOnly.name]! as bool,
                ),
              )
              .then(
                (requests) => requests
                    .map(constellationRequestToGqlMap)
                    .toList(growable: false),
              );
        },
      );
}
