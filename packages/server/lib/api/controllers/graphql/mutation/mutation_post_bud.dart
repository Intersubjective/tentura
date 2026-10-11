import 'package:tentura_server/domain/entity/post_bud.dart';
import 'package:tentura_server/domain/use_case/post_bud_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// `[PostBudInviteeInput!]` typed over `dynamic`, so a decoded
/// `List<dynamic>` of maps passes validation on executors that do not
/// re-type variable lists.
final class _InviteeListType extends GraphQLListType<dynamic, dynamic> {
  _InviteeListType() : super(gqlInputPostBudInvitee.nonNullable());

  @override
  GraphQLType<List<dynamic>, List<dynamic>> coerceToInputObject() => this;
}

/// Budding a Request from a Post (plan C3, Arch §4.2).
final class MutationPostBud extends GqlNodeBase {
  MutationPostBud({PostBudCase? postBudCase}) : _injectedCase = postBudCase;

  final PostBudCase? _injectedCase;

  PostBudCase get _case => _injectedCase ?? GetIt.I<PostBudCase>();

  final _postId = InputFieldString(fieldName: 'postId');
  final _sourceMessageId = InputFieldString(fieldName: 'sourceMessageId');
  final _clientCommandId = InputFieldString(fieldName: 'clientCommandId');
  final _startAt = InputFieldDatetime(fieldName: 'startAt');
  final _endAt = InputFieldDatetime(fieldName: 'endAt');
  final _tags = InputFieldString(fieldName: 'tags');
  final _needs = InputFieldString(fieldName: 'needs');
  final _addressLabel = InputFieldString(fieldName: 'addressLabel');
  final _primaryNeedSlug = InputFieldString(fieldName: 'primaryNeedSlug');
  final _isDiscoverable = InputFieldBool(fieldName: 'isDiscoverable');
  final _closePost = InputFieldBool(fieldName: 'closePost');

  final _invitees = GraphQLFieldInput(
    'invitees',
    _InviteeListType(),
    defaultsToNull: true,
  );

  List<GraphQLObjectField<dynamic, dynamic>> get all => [beaconBudFromPost];

  GraphQLObjectField<dynamic, dynamic> get beaconBudFromPost =>
      GraphQLObjectField(
        'beaconBudFromPost',
        gqlTypePostBudResult.nonNullable(),
        arguments: [
          _postId.field,
          _sourceMessageId.field,
          _clientCommandId.field,
          InputFieldBeaconTitle.fieldNonNullable,
          InputFieldDescription.field,
          InputFieldCoordinates.field,
          InputFieldContext.field,
          _startAt.fieldNullable,
          _endAt.fieldNullable,
          _tags.fieldNullable,
          _needs.fieldNullable,
          _primaryNeedSlug.fieldNullable,
          _addressLabel.fieldNullable,
          _isDiscoverable.fieldNullable,
          _invitees,
          _closePost.fieldNullable,
        ],
        resolve: (_, args) async {
          final result = await _case.budFromPost(
            actorUserId: getCredentials(args).sub,
            postId: _postId.fromArgsNonNullable(args),
            sourceMessageId: _sourceMessageId.fromArgsNonNullable(args),
            clientCommandId: _clientCommandId.fromArgsNonNullable(args),
            title: InputFieldBeaconTitle.fromArgsNonNullable(args),
            description: InputFieldDescription.fromArgs(args),
            context: InputFieldContext.fromArgs(args),
            tags: _tags.fromArgs(args),
            needs: _needs.fromArgs(args),
            primaryNeedSlug: _primaryNeedSlug.fromArgs(args),
            primaryNeedSlugProvided: args.containsKey('primaryNeedSlug'),
            startAt: _startAt.fromArgs(args),
            endAt: _endAt.fromArgs(args),
            coordinates: InputFieldCoordinates.fromArgs(args),
            addressLabel: _addressLabel.fromArgs(args),
            isDiscoverable: _isDiscoverable.fromArgs(args) ?? false,
            invitees: [
              for (final raw
                  in (args[_invitees.name] as List?) ?? const <Object?>[])
                if (raw case final Map<dynamic, dynamic> invitee)
                  PostBudInvitee(
                    userId: invitee['userId']! as String,
                    note: invitee['note'] as String?,
                  ),
            ],
            closePost: _closePost.fromArgs(args) ?? false,
          );
          return postBudResultToGqlMap(result);
        },
      );
}

Map<String, Object?> postBudResultToGqlMap(PostBudResult result) => {
  'outcome': result.outcome,
  'childBeaconId': result.childBeaconId,
  'invitees': [
    for (final invitee in result.invitees)
      {'userId': invitee.userId, 'outcome': invitee.outcome.name},
  ],
};
