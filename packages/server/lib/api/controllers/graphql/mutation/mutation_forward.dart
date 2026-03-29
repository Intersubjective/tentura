import 'package:tentura_server/domain/use_case/forward_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationForward extends GqlNodeBase {
  MutationForward({ForwardCase? forwardCase})
    : _forwardCase = forwardCase ?? GetIt.I<ForwardCase>();

  final ForwardCase _forwardCase;

  final _note = InputFieldString(fieldName: 'note');
  final _context = InputFieldString(fieldName: 'context');
  final _parentEdgeId = InputFieldString(fieldName: 'parentEdgeId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [forward];

  GraphQLObjectField<dynamic, dynamic> get forward => GraphQLObjectField(
    'beaconForward',
    graphQLString.nonNullable(),
    arguments: [
      InputFieldId.field,
      InputFieldRecipientIds.field,
      _note.fieldNullable,
      _context.fieldNullable,
      _parentEdgeId.fieldNullable,
    ],
    resolve: (_, args) => _forwardCase.forward(
      senderId: getCredentials(args).sub,
      beaconId: InputFieldId.fromArgsNonNullable(args),
      recipientIds: InputFieldRecipientIds.fromArgs(args),
      sharedNote: _note.fromArgs(args) ?? '',
      context: _context.fromArgs(args),
      parentEdgeId: _parentEdgeId.fromArgs(args),
    ),
  );
}
