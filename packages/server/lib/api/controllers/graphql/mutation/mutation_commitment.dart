import 'package:tentura_server/domain/use_case/commitment_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationCommitment extends GqlNodeBase {
  MutationCommitment({CommitmentCase? commitmentCase})
    : _commitmentCase = commitmentCase ?? GetIt.I<CommitmentCase>();

  final CommitmentCase _commitmentCase;

  final _message = InputFieldString(fieldName: 'message');

  final _helpTypes = InputFieldStringList(fieldName: 'helpTypes');

  final _uncommitReason = InputFieldString(fieldName: 'uncommitReason');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [commit, withdraw];

  GraphQLObjectField<dynamic, dynamic> get commit => GraphQLObjectField(
    'beaconCommit',
    graphQLBoolean.nonNullable(),
    arguments: [
      InputFieldId.field,
      _message.fieldNullable,
      _helpTypes.fieldNullable,
    ],
    resolve: (_, args) => _commitmentCase
        .commit(
          beaconId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          message: _message.fromArgs(args) ?? '',
          helpTypes: _helpTypes.fromArgs(args),
        )
        .then((_) => true),
  );

  GraphQLObjectField<dynamic, dynamic> get withdraw => GraphQLObjectField(
    'beaconWithdraw',
    graphQLBoolean.nonNullable(),
    arguments: [
      InputFieldId.field,
      _message.fieldNullable,
      _uncommitReason.field,
    ],
    resolve: (_, args) => _commitmentCase
        .withdraw(
          beaconId: InputFieldId.fromArgsNonNullable(args),
          userId: getCredentials(args).sub,
          message: _message.fromArgs(args) ?? '',
          uncommitReason: _uncommitReason.fromArgsNonNullable(args),
        )
        .then((_) => true),
  );
}
