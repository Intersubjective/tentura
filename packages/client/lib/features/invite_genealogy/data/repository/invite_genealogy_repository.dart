import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_model.dart';
import 'package:tentura/data/repository/remote_repository.dart';

import '../../domain/entity/invite_genealogy_graph.dart';
import '../gql/_g/invite_genealogy_between_fetch.req.gql.dart';
import '../gql/_g/invite_genealogy_fetch.req.gql.dart';

@lazySingleton
class InviteGenealogyRepository extends RemoteRepository {
  InviteGenealogyRepository({
    required super.remoteApiService,
    required super.log,
  });

  Future<InviteGenealogyGraph> fetch() async {
    final data = await requestDataOnlineOrThrow(
      GInviteGenealogyReq(),
      label: _label,
    );
    final graph = data.inviteGenealogy;
    if (graph == null) {
      return const InviteGenealogyGraph(
        viewerNodeKey: '',
        nodes: [],
        edges: [],
      );
    }
    return InviteGenealogyGraph(
      viewerNodeKey: graph.viewer_node_key,
      nodes: [
        for (final node in graph.nodes)
          InviteGenealogyNode(
            nodeKey: node.node_key,
            profile: node.user == null
                ? null
                : (node.user! as UserModel).toEntity(),
            deletedAt: _parseDate(node.deleted_at),
            userCreatedAt: _parseDate(node.user_created_at),
          ),
      ],
      edges: [
        for (final edge in graph.edges)
          InviteGenealogyEdge(
            ancestorNodeKey: edge.ancestor_node_key,
            descendantNodeKey: edge.descendant_node_key,
            ancestorUserCreatedAt: _parseDate(edge.ancestor_user_created_at)!,
            descendantUserCreatedAt:
                _parseDate(edge.descendant_user_created_at)!,
            createdAt: _parseDate(edge.created_at)!,
          ),
      ],
    );
  }

  Future<InviteGenealogyGraph> fetchBetween(String targetId) async {
    final data = await requestDataOnlineOrThrow(
      GInviteGenealogyBetweenReq((b) => b..vars.targetId = targetId),
      label: _label,
    );
    final graph = data.inviteGenealogyBetween;
    if (graph == null) {
      return const InviteGenealogyGraph(
        viewerNodeKey: '',
        nodes: [],
        edges: [],
      );
    }
    return InviteGenealogyGraph(
      viewerNodeKey: graph.viewer_node_key,
      targetNodeKey: graph.target_node_key,
      commonAncestorNodeKey: graph.common_ancestor_node_key,
      nodes: [
        for (final node in graph.nodes)
          InviteGenealogyNode(
            nodeKey: node.node_key,
            profile: node.user == null
                ? null
                : (node.user! as UserModel).toEntity(),
            deletedAt: _parseDate(node.deleted_at),
            userCreatedAt: _parseDate(node.user_created_at),
          ),
      ],
      edges: [
        for (final edge in graph.edges)
          InviteGenealogyEdge(
            ancestorNodeKey: edge.ancestor_node_key,
            descendantNodeKey: edge.descendant_node_key,
            ancestorUserCreatedAt: _parseDate(edge.ancestor_user_created_at)!,
            descendantUserCreatedAt:
                _parseDate(edge.descendant_user_created_at)!,
            createdAt: _parseDate(edge.created_at)!,
          ),
      ],
    );
  }

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  static const _label = 'InviteGenealogy';
}
