import 'package:tentura_server/domain/use_case/invite_genealogy_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../mappers/gql_public_user_maps.dart';
import '../mappers/invite_genealogy_gql_maps.dart';

final class QueryInviteGenealogy extends GqlNodeBase {
  QueryInviteGenealogy({InviteGenealogyCase? inviteGenealogyCase})
    : _inviteGenealogyCase =
          inviteGenealogyCase ?? GetIt.I<InviteGenealogyCase>();

  final InviteGenealogyCase _inviteGenealogyCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [inviteGenealogy];

  GraphQLObjectField<dynamic, dynamic> get inviteGenealogy =>
      GraphQLObjectField(
        'inviteGenealogy',
        gqlTypeInviteGenealogy,
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final graph = await _inviteGenealogyCase.fetchLineage(
            viewerId: jwt.sub,
          );
          return inviteGenealogyGraphToGqlMap(
            graph,
            userPublicToGqlMap: userPublicToGqlMap,
          );
        },
      );
}
