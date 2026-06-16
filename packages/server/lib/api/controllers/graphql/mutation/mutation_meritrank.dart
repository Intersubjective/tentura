import 'package:tentura_server/domain/use_case/meritrank_case.dart';
import 'package:tentura_server/domain/use_case/user_trust_edge_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class MutationMeritrank extends GqlNodeBase {
  MutationMeritrank({
    MeritrankCase? meritrankCase,
    UserTrustEdgeCase? trustEdgeCase,
  }) : _meritrankCase = meritrankCase ?? GetIt.I<MeritrankCase>(),
       _trustEdgeCase = trustEdgeCase ?? GetIt.I<UserTrustEdgeCase>();

  final MeritrankCase _meritrankCase;
  final UserTrustEdgeCase _trustEdgeCase;

  final _forceCalculateInput = InputFieldBool(fieldName: 'forceCalculate');
  final _sourceUserIdField = InputFieldString(fieldName: 'sourceUserId');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    meritrankInit,
    trustForceRefreshStar,
    trustForceRefreshAll,
  ];

  GraphQLObjectField<dynamic, dynamic> get meritrankInit => GraphQLObjectField(
    'meritrankInit',
    graphQLInt.nonNullable(),
    arguments: [_forceCalculateInput.fieldNullable],
    resolve: (_, args) {
      final credentials = getCredentials(args);
      return _meritrankCase.init(
        userId: credentials.sub,
        userRoles: credentials.roles,
        forceCalculate: _forceCalculateInput.fromArgs(args),
      );
    },
  );

  GraphQLObjectField<dynamic, dynamic> get trustForceRefreshStar =>
      GraphQLObjectField(
        'trustForceRefreshStar',
        graphQLBoolean.nonNullable(),
        arguments: [_sourceUserIdField.field],
        resolve: (_, args) {
          final credentials = getCredentials(args);
          return _trustEdgeCase
              .forceRefreshStar(
                userId: credentials.sub,
                sourceUserId: _sourceUserIdField.fromArgsNonNullable(args),
                userRoles: credentials.roles,
              )
              .then((_) => true);
        },
      );

  GraphQLObjectField<dynamic, dynamic> get trustForceRefreshAll =>
      GraphQLObjectField(
        'trustForceRefreshAll',
        graphQLBoolean.nonNullable(),
        resolve: (_, args) {
          final credentials = getCredentials(args);
          return _trustEdgeCase
              .forceRefreshAll(
                userId: credentials.sub,
                userRoles: credentials.roles,
              )
              .then((_) => true);
        },
      );
}
