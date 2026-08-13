import 'package:tentura_server/domain/use_case/invitation_case.dart';
import 'package:tentura_server/domain/use_case/user_availability_case.dart';
import 'package:tentura_server/domain/use_case/user_presence_case.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_public_user_maps.dart';

final class QueryInvitation extends GqlNodeBase {
  QueryInvitation({
    InvitationCase? invitationCase,
    UserPresenceCase? userPresenceCase,
    UserAvailabilityCase? userAvailabilityCase,
    VoteUserFriendshipLookupPort? voteUserFriendshipLookup,
  }) : _invitationCase = invitationCase ?? GetIt.I<InvitationCase>(),
       _userPresenceCase = userPresenceCase ?? GetIt.I<UserPresenceCase>(),
       _userAvailabilityCase =
           userAvailabilityCase ?? GetIt.I<UserAvailabilityCase>(),
       _voteUserFriendshipLookup =
           voteUserFriendshipLookup ?? GetIt.I<VoteUserFriendshipLookupPort>();

  final InvitationCase _invitationCase;

  final UserPresenceCase _userPresenceCase;

  final UserAvailabilityCase _userAvailabilityCase;

  final VoteUserFriendshipLookupPort _voteUserFriendshipLookup;

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
      final issuerFriendship =
          jwt.sub != e.issuer.id &&
          await _voteUserFriendshipLookup.isReciprocalSubscribe(
            viewerId: jwt.sub,
            peerId: e.issuer.id,
          );
      issuer['is_mutual_friend'] = issuerFriendship;
      final issuerTrustsViewer =
          jwt.sub != e.issuer.id &&
          await _voteUserFriendshipLookup.isSubscribedTo(
            viewerId: e.issuer.id,
            peerId: jwt.sub,
          );
      issuer['trusts_viewer'] = issuerTrustsViewer;
      final p = await _userPresenceCase.get(e.issuer.id);
      issuer['user_presence'] = p == null
          ? null
          : {
              'last_seen_at': p.lastSeenAt.toUtc().toIso8601String(),
              'status': p.status.index,
            };
      final todayUtc = _userAvailabilityCase.todayUtcFrom(DateTime.timestamp());
      final availabilityEntities = await _userAvailabilityCase.fetchByUserIds({
        e.issuer.id,
      });
      issuer['user_availability'] = userAvailabilityEntityToGqlMap(
        entity: availabilityEntities[e.issuer.id],
        todayUtc: todayUtc,
      );
      map['issuer'] = issuer;
      return map;
    },
  );
}
