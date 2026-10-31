import 'package:tentura_server/domain/entity/author_invite.dart';
import 'package:tentura_server/domain/use_case/author_invite_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// The author-invite lifecycle (plan C4, Arch §5): later invites, accept,
/// decline, revert-decline and withdraw.
final class MutationAuthorInvite extends GqlNodeBase {
  MutationAuthorInvite({AuthorInviteCase? authorInviteCase})
    : _injectedCase = authorInviteCase;

  final AuthorInviteCase? _injectedCase;

  AuthorInviteCase get _case => _injectedCase ?? GetIt.I<AuthorInviteCase>();

  final _beaconId = InputFieldString(fieldName: 'beaconId');
  final _userId = InputFieldString(fieldName: 'userId');
  final _note = InputFieldString(fieldName: 'note');
  final _inviteId = InputFieldString(fieldName: 'inviteId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconAuthorInviteCreate,
    beaconAuthorInviteAccept,
    beaconAuthorInviteDecline,
    beaconAuthorInviteRevertDecline,
    beaconAuthorInviteWithdraw,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconAuthorInviteCreate =>
      GraphQLObjectField(
        'beaconAuthorInviteCreate',
        gqlTypeAuthorInviteCreateResult.nonNullable(),
        arguments: [_beaconId.field, _userId.field, _note.fieldNullable],
        resolve: (_, args) async {
          final result = await _case.create(
            actorUserId: getCredentials(args).sub,
            beaconId: _beaconId.fromArgsNonNullable(args),
            inviteeId: _userId.fromArgsNonNullable(args),
            note: _note.fromArgs(args),
          );
          return {
            'outcome': result.outcome.name,
            'inviteId': result.inviteId,
          };
        },
      );

  GraphQLObjectField<dynamic, dynamic> get beaconAuthorInviteAccept =>
      _transition('beaconAuthorInviteAccept', _case.accept);

  GraphQLObjectField<dynamic, dynamic> get beaconAuthorInviteDecline =>
      _transition('beaconAuthorInviteDecline', _case.decline);

  GraphQLObjectField<dynamic, dynamic> get beaconAuthorInviteRevertDecline =>
      _transition('beaconAuthorInviteRevertDecline', _case.revertDecline);

  GraphQLObjectField<dynamic, dynamic> get beaconAuthorInviteWithdraw =>
      _transition('beaconAuthorInviteWithdraw', _case.withdraw);

  GraphQLObjectField<dynamic, dynamic> _transition(
    String name,
    Future<AuthorInvite> Function({
      required String actorUserId,
      required String inviteId,
    })
    run,
  ) => GraphQLObjectField(
    name,
    gqlTypeAuthorInviteResult.nonNullable(),
    arguments: [_inviteId.field],
    resolve: (_, args) async => authorInviteToGqlMap(
      await run(
        actorUserId: getCredentials(args).sub,
        inviteId: _inviteId.fromArgsNonNullable(args),
      ),
    ),
  );
}

Map<String, Object?> authorInviteToGqlMap(AuthorInvite invite) => {
  'inviteId': invite.id,
  'beaconId': invite.beaconId,
  'status': invite.status.name,
};
