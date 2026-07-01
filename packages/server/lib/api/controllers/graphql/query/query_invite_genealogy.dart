import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/port/merit_score_lookup_port.dart';
import 'package:tentura_server/domain/port/vote_user_friendship_lookup_port.dart';
import 'package:tentura_server/domain/use_case/invite_genealogy_case.dart';

import '../custom_types.dart';
import '../gql_nodel_base.dart';
import '../input/_input_types.dart';
import '../mappers/gql_public_user_maps.dart';
import '../mappers/invite_genealogy_gql_maps.dart';

final class QueryInviteGenealogy extends GqlNodeBase {
  QueryInviteGenealogy({
    InviteGenealogyCase? inviteGenealogyCase,
    MeritScoreLookupPort? meritScoreLookup,
    VoteUserFriendshipLookupPort? voteUserFriendshipLookup,
  }) : _inviteGenealogyCase =
           inviteGenealogyCase ?? GetIt.I<InviteGenealogyCase>(),
       _meritScoreLookup = meritScoreLookup ?? GetIt.I<MeritScoreLookupPort>(),
       _voteUserFriendshipLookup =
           voteUserFriendshipLookup ?? GetIt.I<VoteUserFriendshipLookupPort>();

  final InviteGenealogyCase _inviteGenealogyCase;
  final MeritScoreLookupPort _meritScoreLookup;
  final VoteUserFriendshipLookupPort _voteUserFriendshipLookup;

  static final _targetId = InputFieldString(fieldName: 'target_id');
  static final _nodeKey = InputFieldString(fieldName: 'node_key');
  static final _nodeKeys = InputFieldStringList(fieldName: 'node_keys');
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
    inviteGenealogyChildCounts,
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
          final overlay = await _viewerRelativeOverlay(
            viewerId: jwt.sub,
            context: _queryContext(args),
            userIds: graph.nodes.map((n) => n.user?.id).whereType<String>(),
          );
          return inviteGenealogyGraphToGqlMap(
            graph,
            userPublicToGqlMap: userPublicToGqlMap,
            scoresByUserId: overlay.scores,
            mutualFriendUserIds: overlay.mutualFriends,
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
          final overlay = await _viewerRelativeOverlay(
            viewerId: jwt.sub,
            context: _queryContext(args),
            userIds: graph.nodes.map((n) => n.user?.id).whereType<String>(),
          );
          return inviteGenealogyGraphToGqlMap(
            graph,
            userPublicToGqlMap: userPublicToGqlMap,
            scoresByUserId: overlay.scores,
            mutualFriendUserIds: overlay.mutualFriends,
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
      final jwt = getCredentials(args);
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
      final overlay = await _viewerRelativeOverlay(
        viewerId: jwt.sub,
        context: _queryContext(args),
        userIds: page.nodes.map((n) => n.user?.id).whereType<String>(),
      );
      return inviteGenealogyChildrenPageToGqlMap(
        page,
        userPublicToGqlMap: userPublicToGqlMap,
        scoresByUserId: overlay.scores,
        mutualFriendUserIds: overlay.mutualFriends,
      );
    },
  );

  GraphQLObjectField<dynamic, dynamic> get inviteGenealogyChildCounts =>
      GraphQLObjectField(
        'inviteGenealogyChildCounts',
        GraphQLListType(
          gqlTypeInviteGenealogyChildCount.nonNullable(),
        ).nonNullable(),
        arguments: [_nodeKeys.field],
        resolve: (_, args) async {
          final nodeKeys = _nodeKeys
              .fromArgsNonNullable(args)
              .map((key) => key.trim())
              .toSet()
              .toList(growable: false);
          for (final nodeKey in nodeKeys) {
            if (!_nodeKeyPattern.hasMatch(nodeKey)) {
              throw ArgumentError.value(
                nodeKey,
                _nodeKeys.field.name,
                'must contain only valid invite-genealogy node keys',
              );
            }
          }
          final counts = await _inviteGenealogyCase.fetchChildCounts(
            nodeKeys: nodeKeys,
          );
          return [
            for (final nodeKey in nodeKeys)
              {
                'node_key': nodeKey,
                'total_children': counts[nodeKey] ?? 0,
              },
          ];
        },
      );

  static String _queryContext(Map<String, dynamic> args) =>
      args[kGlobalInputQueryContext] as String? ?? '';

  /// Attaches viewer-relative MeritRank scores and mutual-friend status to a
  /// batch of genealogy node user ids in two extra queries total (not one per
  /// node): [MeritScoreLookupPort.reciprocalScoresForViewer] returns all of
  /// the viewer's reciprocal-positive peers in one call, and
  /// [VoteUserFriendshipLookupPort.reciprocalPositivePeerIds] checks the
  /// whole candidate batch in one indexed round trip.
  Future<
    ({
      Map<String, MutualScoreRecord> scores,
      Set<String> mutualFriends,
    })
  >
  _viewerRelativeOverlay({
    required String viewerId,
    required String context,
    required Iterable<String> userIds,
  }) async {
    final candidateIds = userIds
        .where((id) => id.isNotEmpty && id != viewerId)
        .toSet();
    if (candidateIds.isEmpty) {
      return (
        scores: const <String, MutualScoreRecord>{},
        mutualFriends: const <String>{},
      );
    }
    final scores = await _meritScoreLookup.reciprocalScoresForViewer(
      viewerId: viewerId,
      context: context,
    );
    final mutualFriends = await _voteUserFriendshipLookup
        .reciprocalPositivePeerIds(viewerId: viewerId, peerIds: candidateIds);
    return (scores: scores, mutualFriends: mutualFriends);
  }
}
