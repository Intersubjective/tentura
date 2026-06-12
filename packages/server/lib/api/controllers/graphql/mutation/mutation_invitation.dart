import 'package:tentura_server/domain/use_case/invitation_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationInvitation extends GqlNodeBase {
  MutationInvitation({InvitationCase? invitationCase})
    : _invitationCase = invitationCase ?? GetIt.I<InvitationCase>();

  final InvitationCase _invitationCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    create,
    update,
    accept,
    delete,
  ];

  static final _beaconIdField = GraphQLFieldInput<String?, String?>(
    'beaconId',
    graphQLString,
    defaultsToNull: true,
  );

  static final _addresseeName = InputFieldString(fieldName: 'addresseeName');

  GraphQLObjectField<dynamic, dynamic> get create => GraphQLObjectField(
    'invitationCreate',
    gqlTypeInvitation.nonNullable(),
    arguments: [_addresseeName.field, _beaconIdField],
    resolve: (_, args) => _invitationCase
        .create(
          userId: getCredentials(args).sub,
          addresseeName: _addresseeName.fromArgsNonNullable(args),
          beaconId: args['beaconId'] as String?,
        )
        .then((e) => e.asMap),
  );

  GraphQLObjectField<dynamic, dynamic> get update => GraphQLObjectField(
    'invitationUpdate',
    gqlTypeInvitation.nonNullable(),
    arguments: [InputFieldId.field, _addresseeName.field],
    resolve: (_, args) => _invitationCase
        .update(
          invitationId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          addresseeName: _addresseeName.fromArgsNonNullable(args),
        )
        .then((e) => e.asMap),
  );

  GraphQLObjectField<dynamic, dynamic> get accept => GraphQLObjectField(
    'invitationAccept',
    graphQLBoolean.nonNullable(),
    arguments: [InputFieldId.field],
    resolve: (_, args) => _invitationCase.accept(
      invitationId: InputFieldId.fromArgsNonNullable(args),
      userId: getCredentials(args).sub,
    ),
  );

  GraphQLObjectField<dynamic, dynamic> get delete => GraphQLObjectField(
    'invitationDelete',
    graphQLBoolean.nonNullable(),
    arguments: [InputFieldId.field],
    resolve: (_, args) => _invitationCase.delete(
      invitationId: InputFieldId.fromArgsNonNullable(args),
      userId: getCredentials(args).sub,
    ),
  );
}
