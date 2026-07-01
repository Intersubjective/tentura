import 'package:tentura_server/domain/use_case/invite_genealogy_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_public_user_maps.dart';
import '../mappers/invite_genealogy_gql_maps.dart';

final class QueryInviteGenealogy extends GqlNodeBase {
  QueryInviteGenealogy({InviteGenealogyCase? inviteGenealogyCase})
    : _inviteGenealogyCase =
          inviteGenealogyCase ?? GetIt.I<InviteGenealogyCase>();

  final InviteGenealogyCase _inviteGenealogyCase;

  static final _targetId = InputFieldString(fieldName: 'target_id');
  static final _nodeKey = InputFieldString(fieldName: 'node_key');
  static final _afterCreatedAt = InputFieldDatetime(
    fieldName: 'after_created_at',
  );
  static final _afterNodeKey = InputFieldString(fieldName: 'after_node_key');
  static final _limit = InputFieldInt(fieldName: 'limit');
  static final _nodeKeyPattern = RegExp(r'^G[A-Za-z0-9_-]{43}$');

  List<GraphQLObjectField<dynamic, dynamic>> get all => [
    inviteGenealogy,
    inviteGenealogyBetween,
    inviteGenealogyChildren,
  ];

  GraphQLObjectField<dynamic, dynamic> get inviteGenealogy =>
      GraphQLObjectField(
        'inviteGenealogy',
        gqlTypeInviteGenealogy,
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final graph = await _inviteGenealogyCase.fetchLineage(
            viewerId: jwt.sub,
          );
          return inviteGenealogyGraphToGqlMap(
            graph,
            userPublicToGqlMap: userPublicToGqlMap,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic> get inviteGenealogyBetween =>
      GraphQLObjectField(
        'inviteGenealogyBetween',
        gqlTypeInviteGenealogy,
        arguments: [_targetId.field],
        resolve: (_, args) async {
          final jwt = getCredentials(args);
          final graph = await _inviteGenealogyCase.fetchLineageBetween(
            viewerId: jwt.sub,
            targetId: _targetId.fromArgsNonNullable(args),
          );
          return inviteGenealogyGraphToGqlMap(
            graph,
            userPublicToGqlMap: userPublicToGqlMap,
          );
        },
      );

  GraphQLObjectField<dynamic, dynamic>
  get inviteGenealogyChildren => GraphQLObjectField(
    'inviteGenealogyChildren',
    gqlTypeInviteGenealogyChildrenPage,
    arguments: [
      _nodeKey.field,
      _afterCreatedAt.fieldNullable,
      _afterNodeKey.fieldNullable,
      _limit.fieldNullable,
    ],
    resolve: (_, args) async {
      getCredentials(args);
      final nodeKey = _nodeKey.fromArgsNonNullable(args).trim();
      if (!_nodeKeyPattern.hasMatch(nodeKey)) {
        throw ArgumentError.value(
          nodeKey,
          _nodeKey.field.name,
          'must be a valid invite-genealogy node key',
        );
      }

      final afterCreatedAt = _afterCreatedAt.fromArgs(args);
      final afterNodeKey = _afterNodeKey.fromArgs(args)?.trim();
      final hasAfterCreatedAtArg =
          args[_afterCreatedAt.fieldNullable.name] != null;
      final hasAfterNodeKeyArg = args[_afterNodeKey.fieldNullable.name] != null;

      if (hasAfterCreatedAtArg && afterCreatedAt == null) {
        throw ArgumentError.value(
          args[_afterCreatedAt.fieldNullable.name],
          _afterCreatedAt.fieldNullable.name,
          'must be a non-empty ISO-8601 date-time',
        );
      }
      if (hasAfterNodeKeyArg &&
          (afterNodeKey == null || afterNodeKey.isEmpty)) {
        throw ArgumentError.value(
          args[_afterNodeKey.fieldNullable.name],
          _afterNodeKey.fieldNullable.name,
          'must be a non-empty node key',
        );
      }
      if (hasAfterCreatedAtArg != hasAfterNodeKeyArg) {
        throw ArgumentError(
          'after_created_at and after_node_key must both be provided or both omitted',
        );
      }

      final page = await _inviteGenealogyCase.fetchChildren(
        nodeKey: nodeKey,
        afterCreatedAt: afterCreatedAt,
        afterNodeKey: afterNodeKey,
        limit: _limit.fromArgs(args) ?? 10,
      );
      return inviteGenealogyChildrenPageToGqlMap(
        page,
        userPublicToGqlMap: userPublicToGqlMap,
      );
    },
  );
}
