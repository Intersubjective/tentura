import 'package:tentura_server/domain/use_case/forward_candidates_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_public_user_maps.dart';

/// Root query field [forwardCandidates]: mutually visible users for the JWT
/// viewer, with MeritRank value scores from `person_visibility_peers`.
final class QueryForwardCandidates extends GqlNodeBase {
  QueryForwardCandidates({ForwardCandidatesCase? forwardCandidatesCase})
    : _forwardCandidatesCase =
          forwardCandidatesCase ?? GetIt.I<ForwardCandidatesCase>();

  final ForwardCandidatesCase _forwardCandidatesCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [forwardCandidates];

  GraphQLObjectField<dynamic, dynamic> get forwardCandidates =>
      GraphQLObjectField(
        'forwardCandidates',
        GraphQLListType(gqlTypeUserPublic.nonNullable()).nonNullable(),
        arguments: [InputFieldContext.fieldNonNullable],
        resolve: (_, args) async {
          final rows = await _forwardCandidatesCase.fetch(
            viewerId: getCredentials(args).sub,
            context: InputFieldContext.fromArgsNonNullable(args),
          );
          return rows.map(userPublicToGqlMap).toList();
        },
      );
}
