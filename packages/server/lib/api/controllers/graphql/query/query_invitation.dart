import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/data/repository/vote_user_friendship_lookup.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryInvitation extends GqlNodeBase {
  QueryInvitation({
    InvitationCase? invitationCase,
    UserPresenceCase? userPresenceCase,
    VoteUserFriendshipLookup? voteUserFriendshipLookup,
  }) : _invitationCase = invitationCase ?? GetIt.I<InvitationCase>(),
       _userPresenceCase = userPresenceCase ?? GetIt.I<UserPresenceCase>(),
       _voteUserFriendshipLookup =
           voteUserFriendshipLookup ?? GetIt.I<VoteUserFriendshipLookup>();

  final InvitationCase _invitationCase;

  final UserPresenceCase _userPresenceCase;

  final VoteUserFriendshipLookup _voteUserFriendshipLookup;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [invitationById];

  GraphQLObjectField<dynamic, dynamic> get invitationById => GraphQLObjectField(
    'invitationById',
    gqlTypeInvitation,
    arguments: [InputFieldId.field],
    resolve: (_, args) async {
      final jwt = getCredentials(args);
      final e = await _invitationCase.fetchById(
        invitationId: InputFieldId.fromArgsNonNullable(args),
      );
      final map = Map<String, dynamic>.from(e.asMapWithIssuer);
      final issuer = Map<String, dynamic>.from(map['issuer']! as Map);
      final issuerFriendship = jwt.sub != e.issuer.id &&
          await _voteUserFriendshipLookup.isReciprocalSubscribe(
            viewerId: jwt.sub,
            peerId: e.issuer.id,
          );
      issuer['is_mutual_friend'] = issuerFriendship;
      final p = await _userPresenceCase.get(e.issuer.id);
      issuer['user_presence'] = p == null
          ? null
          : {
              'last_seen_at': p.lastSeenAt.toUtc().toIso8601String(),
              'status': p.status.index,
            };
      map['issuer'] = issuer;
      return map;
    },
  );
}
