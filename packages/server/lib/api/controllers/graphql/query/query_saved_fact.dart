import 'package:tentura_server/domain/use_case/saved_fact_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';

final class QuerySavedFact extends GqlNodeBase {
  QuerySavedFact({SavedFactCase? savedFactCase})
    : _case = savedFactCase ?? GetIt.I<SavedFactCase>();

  final SavedFactCase _case;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    beaconFactCardSavedList,
    beaconFactCardSearch,
  ];

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardSavedList =>
      GraphQLObjectField(
        'BeaconFactCardSavedList',
        GraphQLListType(
          gqlTypeBeaconFactCardSavedRow.nonNullable(),
        ).nonNullable(),
        resolve: (_, args) => _case.list(userId: getCredentials(args).sub),
      );

  GraphQLObjectField<dynamic, dynamic> get beaconFactCardSearch =>
      GraphQLObjectField(
        'BeaconFactCardSearch',
        GraphQLListType(
          gqlTypeBeaconFactCardSearchRow.nonNullable(),
        ).nonNullable(),
        arguments: [
          GraphQLFieldInput('query', graphQLString.nonNullable()),
          GraphQLFieldInput('excludeBeaconId', graphQLString),
        ],
        resolve: (_, args) => _case.search(
          userId: getCredentials(args).sub,
          query: args['query']! as String,
          excludeBeaconId: args['excludeBeaconId'] as String?,
        ),
      );
}
