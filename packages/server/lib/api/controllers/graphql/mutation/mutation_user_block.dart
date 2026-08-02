import 'package:tentura_server/domain/use_case/user_block_case.dart';

import '../gql_nodel_base.dart';
import '../input/_input_types.dart';

/// User blocking mutations — blocker id comes from JWT only.
final class MutationUserBlock extends GqlNodeBase {
  MutationUserBlock({UserBlockCase? userBlockCase})
    : _userBlockCase = userBlockCase ?? GetIt.I<UserBlockCase>();

  final UserBlockCase _userBlockCase;

  static final _objectId = InputFieldString(fieldName: 'objectId');
  static final _cascadeMode = InputFieldInt(fieldName: 'cascadeMode');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    userBlock,
    userUnblock,
    userBlockPromote,
  ];

  GraphQLObjectField<dynamic, dynamic> get userBlock => GraphQLObjectField(
    'userBlock',
    graphQLBoolean.nonNullable(),
    arguments: [_objectId.field, _cascadeMode.fieldNullable],
    resolve: (_, args) async {
      final jwt = getCredentials(args);
      await _userBlockCase.block(
        blockerId: jwt.sub,
        blockedId: _objectId.fromArgsNonNullable(args),
        cascadeMode: _cascadeMode.fromArgs(args) ?? 0,
      );
      return true;
    },
  );

  GraphQLObjectField<dynamic, dynamic> get userUnblock => GraphQLObjectField(
    'userUnblock',
    graphQLBoolean.nonNullable(),
    arguments: [_objectId.field],
    resolve: (_, args) async {
      final jwt = getCredentials(args);
      await _userBlockCase.unblock(
        blockerId: jwt.sub,
        blockedId: _objectId.fromArgsNonNullable(args),
      );
      return true;
    },
  );

  GraphQLObjectField<dynamic, dynamic> get userBlockPromote =>
      GraphQLObjectField(
        'userBlockPromote',
        graphQLBoolean.nonNullable(),
        arguments: [_objectId.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          await _userBlockCase.promoteToDirect(
            blockerId: jwt.sub,
            blockedId: _objectId.fromArgsNonNullable(args),
          );
          return true;
        },
      );
}
