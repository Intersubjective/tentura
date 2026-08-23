import 'package:tentura_server/domain/use_case/forward_candidate_context_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/forward_candidate_context_gql_maps.dart';

/// Returns one deterministic provenance path from a capped, authorized
/// MeritRank graph snapshot for the JWT viewer.
final class QueryForwardCandidateContext extends GqlNodeBase {
  QueryForwardCandidateContext({
    ForwardCandidateContextCase? forwardCandidateContextCase,
  }) : _forwardCandidateContextCase =
           forwardCandidateContextCase ??
           GetIt.I<ForwardCandidateContextCase>();

  final ForwardCandidateContextCase _forwardCandidateContextCase;

  static final _candidateId = InputFieldString(fieldName: 'candidateId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    forwardCandidateContext,
  ];

  GraphQLObjectField<dynamic, dynamic> get forwardCandidateContext =>
      GraphQLObjectField(
        'forwardCandidateContext',
        gqlTypeForwardCandidateContext.nonNullable(),
        arguments: [_candidateId.field, InputFieldContext.fieldNonNullable],
        resolve: (_, args) => _forwardCandidateContextCase
            .load(
              viewerId: getCredentials(args).sub,
              candidateId: _candidateId.fromArgsNonNullable(args),
              context: InputFieldContext.fromArgsNonNullable(args),
            )
            .then(forwardCandidateContextToGqlMap),
      );
}
