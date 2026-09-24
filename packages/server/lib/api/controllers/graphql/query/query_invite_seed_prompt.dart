import 'package:tentura_server/domain/use_case/invite_seed_attestation_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import 'query_capability_projection.dart';

final class QueryInviteSeedPrompt extends GqlNodeBase {
  QueryInviteSeedPrompt({
    InviteSeedAttestationCase? inviteSeedAttestationCase,
  }) : _inviteSeedAttestationCase =
            inviteSeedAttestationCase ?? GetIt.I<InviteSeedAttestationCase>();

  final InviteSeedAttestationCase _inviteSeedAttestationCase;

  static final _subjectId = InputFieldString(fieldName: 'subjectId');
  static final _subjectIds = InputFieldStringList(fieldName: 'subjectIds');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
        inviteSeedPromptState,
        invitePromptStates,
      ];

  GraphQLObjectField<dynamic, dynamic> get inviteSeedPromptState =>
      GraphQLObjectField(
        'inviteSeedPromptState',
        gqlTypeInviteSeedPromptState.nonNullable(),
        arguments: [_subjectId.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final state = await _inviteSeedAttestationCase.promptStateFor(
            actorId: jwt.sub,
            subjectId: _subjectId.fromArgsNonNullable(args),
          );
          return QueryCapabilityProjection.promptStateToGql(state);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get invitePromptStates =>
      GraphQLObjectField(
        'invitePromptStates',
        GraphQLListType(gqlTypeInviteSeedPromptState.nonNullable())
            .nonNullable(),
        arguments: [_subjectIds.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final subjectIds = _subjectIds.fromArgsNonNullable(args);
          if (subjectIds.length > 100) {
            throw ArgumentError.value(
              subjectIds.length,
              'subjectIds',
              'must contain at most 100 ids',
            );
          }
          final states = await _inviteSeedAttestationCase.promptStatesFor(
            actorId: jwt.sub,
            subjectIds: subjectIds,
          );
          return states
              .map(QueryCapabilityProjection.promptStateToGql)
              .toList(growable: false);
        },
      );
}
