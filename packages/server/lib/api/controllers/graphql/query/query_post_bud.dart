import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/use_case/post_bud_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Invite candidates for budding a Request from a Post (plan C3).
final class QueryPostBud extends GqlNodeBase {
  QueryPostBud({PostBudCase? postBudCase}) : _injectedCase = postBudCase;

  final PostBudCase? _injectedCase;

  PostBudCase get _case => _injectedCase ?? GetIt.I<PostBudCase>();

  final _postId = InputFieldString(fieldName: 'postId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    postBudInviteCandidates,
  ];

  GraphQLObjectField<dynamic, dynamic> get postBudInviteCandidates =>
      GraphQLObjectField(
        'postBudInviteCandidates',
        GraphQLListType(
          gqlTypePostBudInviteCandidate.nonNullable(),
        ).nonNullable(),
        arguments: [_postId.field],
        resolve: (_, args) async {
          final candidates = await _case.inviteCandidates(
            actorUserId: getCredentials(args).sub,
            postId: _postId.fromArgsNonNullable(args),
          );
          return [
            for (final c in candidates)
              {
                'userId': c.userId,
                'warm': c.warm,
                'outcome': PostBudInviteOutcome.fromReason(c.reason).name,
                'pretick': c.pretick,
                'viaUserId': c.viaUserId,
                'hasWritten': c.hasWritten,
              },
          ];
        },
      );
}
