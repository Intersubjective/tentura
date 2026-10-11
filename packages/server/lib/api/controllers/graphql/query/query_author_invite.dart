import 'package:tentura_server/domain/use_case/author_invite_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// Author-invite read projections (plan C6): the invitee's pending invites
/// for the «Для вас» card, and the author's invites on their Request.
final class QueryAuthorInvite extends GqlNodeBase {
  QueryAuthorInvite({AuthorInviteCase? authorInviteCase})
    : _injectedCase = authorInviteCase;

  final AuthorInviteCase? _injectedCase;

  AuthorInviteCase get _case => _injectedCase ?? GetIt.I<AuthorInviteCase>();

  final _beaconId = InputFieldString(fieldName: 'beaconId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    myPendingAuthorInvites,
    beaconAuthorInvites,
    beaconBudObservers,
  ];

  GraphQLObjectField<dynamic, dynamic> get myPendingAuthorInvites =>
      GraphQLObjectField(
        'myPendingAuthorInvites',
        GraphQLListType(
          gqlTypePendingAuthorInvite.nonNullable(),
        ).nonNullable(),
        resolve: (_, args) async {
          final invites = await _case.myPendingInvites(
            actorUserId: getCredentials(args).sub,
          );
          return [
            for (final i in invites)
              {
                'inviteId': i.inviteId,
                'beaconId': i.beaconId,
                'beaconTitle': i.beaconTitle,
                'inviterId': i.inviterId,
                'sourcePostId': i.sourcePostId,
                'note': i.note,
                'createdAt': i.createdAt.toUtc().toIso8601String(),
              },
          ];
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconAuthorInvites =>
      GraphQLObjectField(
        'beaconAuthorInvites',
        GraphQLListType(gqlTypeBeaconAuthorInvite.nonNullable()).nonNullable(),
        arguments: [_beaconId.field],
        resolve: (_, args) async {
          final invites = await _case.beaconInvites(
            actorUserId: getCredentials(args).sub,
            beaconId: _beaconId.fromArgsNonNullable(args),
          );
          return [
            for (final i in invites)
              {
                'inviteId': i.id,
                'inviteeId': i.inviteeId,
                'status': i.status.name,
                'note': i.note,
                'createdAt': i.createdAt?.toUtc().toIso8601String(),
              },
          ];
        },
      );

  /// The snapshot observers of a budded Request, for its author (plan D4).
  GraphQLObjectField<dynamic, dynamic> get beaconBudObservers =>
      GraphQLObjectField(
        'beaconBudObservers',
        GraphQLListType(graphQLString.nonNullable()).nonNullable(),
        arguments: [_beaconId.field],
        resolve: (_, args) => _case.budObservers(
          actorUserId: getCredentials(args).sub,
          beaconId: _beaconId.fromArgsNonNullable(args),
        ),
      );
}
