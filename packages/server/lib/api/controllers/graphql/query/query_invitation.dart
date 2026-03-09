import 'package:tentura_server/domain/use_case/invitation_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryInvitation extends GqlNodeBase {
  QueryInvitation({InvitationCase? invitationCase})
    : _invitationCase = invitationCase ?? GetIt.I<InvitationCase>();

  final InvitationCase _invitationCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [invitationById];

  GraphQLObjectField<dynamic, dynamic> get invitationById => GraphQLObjectField(
    'invitationById',
    gqlTypeInvitation,
    arguments: [InputFieldId.field],
    resolve: (_, args) => _invitationCase
        .fetchById(
          invitationId: InputFieldId.fromArgsNonNullable(args),
        )
        .then((e) => e.asMap),
  );
}
