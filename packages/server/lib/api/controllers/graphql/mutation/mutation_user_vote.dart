import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationUserVote extends GqlNodeBase {
  MutationUserVote({UserTrustEdgeCase? trustEdgeCase})
    : _trustEdgeCase = trustEdgeCase ?? GetIt.I<UserTrustEdgeCase>();

  final UserTrustEdgeCase _trustEdgeCase;

  final _objectIdField = InputFieldString(fieldName: 'objectId');
  final _amountField = InputFieldInt(fieldName: 'amount');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    userSubscribe,
    userUnsubscribe,
    userVote,
  ];

  GraphQLObjectField<dynamic, dynamic> get userSubscribe =>
      GraphQLObjectField(
        'userSubscribe',
        graphQLInt.nonNullable(),
        arguments: [_objectIdField.field],
        resolve: (_, args) {
          final credentials = getCredentials(args);
          return _trustEdgeCase.setUserVote(
            subjectUserId: credentials.sub,
            objectUserId: _objectIdField.fromArgsNonNullable(args),
            amount: 1,
          ).then((_) => 1);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get userUnsubscribe =>
      GraphQLObjectField(
        'userUnsubscribe',
        graphQLInt.nonNullable(),
        arguments: [_objectIdField.field],
        resolve: (_, args) {
          final credentials = getCredentials(args);
          return _trustEdgeCase.setUserVote(
            subjectUserId: credentials.sub,
            objectUserId: _objectIdField.fromArgsNonNullable(args),
            amount: 0,
          ).then((_) => 0);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get userVote => GraphQLObjectField(
    'userVote',
    graphQLInt.nonNullable(),
    arguments: [
      _objectIdField.field,
      _amountField.fieldNullable,
    ],
    resolve: (_, args) {
      final credentials = getCredentials(args);
      final amount = _amountField.fromArgs(args);
      if (amount == null || amount < -1 || amount > 1) {
        throw ArgumentError.value(amount, 'amount', 'must be -1, 0, or 1');
      }
      return _trustEdgeCase
          .setUserVote(
            subjectUserId: credentials.sub,
            objectUserId: _objectIdField.fromArgsNonNullable(args),
            amount: amount,
          )
          .then((_) => amount);
    },
  );
}
