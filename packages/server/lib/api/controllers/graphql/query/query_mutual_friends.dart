import 'package:tentura_server/domain/use_case/mutual_friends_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

final class QueryMutualFriends extends GqlNodeBase {
  QueryMutualFriends({MutualFriendsCase? mutualFriendsCase})
    : _mutualFriendsCase = mutualFriendsCase ?? GetIt.I<MutualFriendsCase>();

  final MutualFriendsCase _mutualFriendsCase;

  List<GraphQLObjectField<dynamic, dynamic>> get all => [mutualFriends];

  GraphQLObjectField<dynamic, dynamic> get mutualFriends =>
      GraphQLObjectField(
        'mutualFriends',
        GraphQLListType(gqlTypeUserPublic.nonNullable()),
        arguments: [InputFieldId.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final bobId = InputFieldId.fromArgsNonNullable(args);
          final ctx = args[kGlobalInputQueryContext] as String? ?? '';
          return _mutualFriendsCase.fetchMutualFriends(
            aliceId: jwt.sub,
            bobId: bobId,
            context: ctx,
          );
        },
      );
}
