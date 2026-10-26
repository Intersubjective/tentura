import 'package:tentura_server/consts/constellation_consts.dart';
import 'package:tentura_server/domain/use_case/constellation_trust_chain_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

final class QueryConstellationTrustChain extends GqlNodeBase {
  QueryConstellationTrustChain({ConstellationTrustChainCase? case_})
    : _case = case_ ?? GetIt.I<ConstellationTrustChainCase>();

  final ConstellationTrustChainCase _case;

  final GraphQLFieldInput<String, String> _personId = GraphQLFieldInput(
    'personId',
    graphQLString.nonNullable(),
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    constellationTrustChain,
  ];

  GraphQLObjectField<dynamic, dynamic> get constellationTrustChain =>
      GraphQLObjectField(
        'constellationTrustChain',
        GraphQLListType(
          gqlTypeConstellationTrustChainPerson.nonNullable(),
        ),
        arguments: [_personId],
        resolve: (_, args) async {
          final viewerId = getCredentials(args).sub;
          final people = await _case.trustChain(
            viewerId: viewerId,
            context: kConstellationContext,
            personId: (args[_personId.name]! as String).trim(),
          );
          return [
            for (final p in people)
              {'userId': p.userId, 'displayName': p.displayName},
          ];
        },
      );
}
