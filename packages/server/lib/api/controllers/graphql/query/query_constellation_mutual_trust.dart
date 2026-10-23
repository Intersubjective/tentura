import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/use_case/constellation_mutual_trust_case.dart';

import '../gql_nodel_base.dart';

/// Root query field [constellationMutualTrust]: by id, the people a selected
/// person on the JWT viewer's field trusts both ways, among those the viewer
/// may see (the field's own edge rules). The MeritRank context is pinned
/// server-side, as for `constellationField`.
final class QueryConstellationMutualTrust extends GqlNodeBase {
  QueryConstellationMutualTrust({ConstellationMutualTrustCase? case_})
    : _case = case_ ?? GetIt.I<ConstellationMutualTrustCase>();

  final ConstellationMutualTrustCase _case;

  final GraphQLFieldInput<String, String> _personId = GraphQLFieldInput(
    'personId',
    graphQLString.nonNullable(),
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationMutualTrust,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationMutualTrust =>
      GraphQLObjectField(
        'constellationMutualTrust',
        GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        arguments: [_personId],
        resolve: (_, args) {
          final viewerId = getCredentials(args).sub;
          final personId = (args[_personId.name]! as String).trim();
          return _case
              .mutualTrustPartners(
                viewerId: viewerId,
                context: kConstellationContext,
                personId: personId,
              )
              .then((ids) => ids.toList()..sort());
        },
      );
}
