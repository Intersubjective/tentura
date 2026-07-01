import 'package:tentura_server/domain/entity/gql_public/image_public_record.dart';
import 'package:tentura_server/domain/entity/gql_public/mutual_score_record.dart';
import 'package:tentura_server/domain/entity/gql_public/user_public_record.dart';
import 'package:tentura_server/domain/entity/invite_genealogy_graph_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

Map<String, dynamic> inviteGenealogyGraphToGqlMap(
  InviteGenealogyGraphEntity graph, {
  required Map<String, dynamic> Function(UserPublicRecord) userPublicToGqlMap,
  Map<String, MutualScoreRecord> scoresByUserId = const {},
  Set<String> mutualFriendUserIds = const {},
}) => {
  'viewer_node_key': graph.viewerNodeKey,
  'target_node_key': graph.targetNodeKey,
  'common_ancestor_node_key': graph.commonAncestorNodeKey,
  'nodes': [
    for (final node in graph.nodes)
      inviteGenealogyNodeToGqlMap(
        node,
        userPublicToGqlMap: userPublicToGqlMap,
        scoresByUserId: scoresByUserId,
        mutualFriendUserIds: mutualFriendUserIds,
      ),
  ],
  'edges': [
    for (final edge in graph.edges) inviteGenealogyEdgeToGqlMap(edge),
  ],
};

Map<String, dynamic> inviteGenealogyChildrenPageToGqlMap(
  InviteGenealogyChildrenPageEntity page, {
  required Map<String, dynamic> Function(UserPublicRecord) userPublicToGqlMap,
  Map<String, MutualScoreRecord> scoresByUserId = const {},
  Set<String> mutualFriendUserIds = const {},
}) => {
  'nodes': [
    for (final node in page.nodes)
      inviteGenealogyNodeToGqlMap(
        node,
        userPublicToGqlMap: userPublicToGqlMap,
        scoresByUserId: scoresByUserId,
        mutualFriendUserIds: mutualFriendUserIds,
      ),
  ],
  'edges': [
    for (final edge in page.edges) inviteGenealogyEdgeToGqlMap(edge),
  ],
};

Map<String, dynamic> inviteGenealogyNodeToGqlMap(
  InviteGenealogyNodeEntity node, {
  required Map<String, dynamic> Function(UserPublicRecord) userPublicToGqlMap,
  Map<String, MutualScoreRecord> scoresByUserId = const {},
  Set<String> mutualFriendUserIds = const {},
}) {
  final user = node.user;
  return {
    'node_key': node.nodeKey,
    'deleted_at': node.deletedAt?.toUtc().toIso8601String(),
    'user_created_at': node.userCreatedAt?.toUtc().toIso8601String(),
    'user': user == null
        ? null
        : userPublicToGqlMap(
            _userToPublic(
              user,
              score: scoresByUserId[user.id],
              isMutualFriend: mutualFriendUserIds.contains(user.id),
            ),
          ),
  };
}

Map<String, dynamic> inviteGenealogyEdgeToGqlMap(
  InviteGenealogyEdgeEntity edge,
) => {
  'ancestor_node_key': edge.ancestorNodeKey,
  'descendant_node_key': edge.descendantNodeKey,
  'ancestor_user_created_at': edge.ancestorUserCreatedAt
      .toUtc()
      .toIso8601String(),
  'descendant_user_created_at': edge.descendantUserCreatedAt
      .toUtc()
      .toIso8601String(),
  'created_at': edge.createdAt.toUtc().toIso8601String(),
};

UserPublicRecord _userToPublic(
  UserEntity user, {
  required bool isMutualFriend,
  MutualScoreRecord? score,
}) {
  final image = user.image;
  return UserPublicRecord(
    id: user.id,
    displayName: user.displayName,
    handle: user.handle.trim().isEmpty ? null : user.handle.trim(),
    description: user.description,
    isMutualFriend: isMutualFriend,
    scores: score == null ? const [] : [score],
    image: image == null
        ? null
        : ImagePublicRecord(
            id: image.id,
            hash: image.blurHash,
            height: image.height,
            width: image.width,
            authorId: image.authorId,
            createdAt: image.createdAt.toUtc(),
          ),
  );
}
