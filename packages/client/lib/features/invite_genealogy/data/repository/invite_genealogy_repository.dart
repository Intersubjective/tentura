import 'package:injectable/injectable.dart';

import 'package:tentura/data/model/user_public_model.dart';
import 'package:tentura/data/repository/remote_repository.dart';
import 'package:tentura/features/graph/data/repository/graph_source_repository.dart';
import 'package:tentura/features/graph/domain/entity/edge_directed.dart';

import '../../domain/entity/invite_genealogy_graph.dart';
import '../gql/_g/invite_genealogy_between_fetch.req.gql.dart';
import '../gql/_g/invite_genealogy_child_counts_fetch.req.gql.dart';
import '../gql/_g/invite_genealogy_children_fetch.req.gql.dart';
import '../gql/_g/invite_genealogy_fetch.req.gql.dart';

@lazySingleton
class InviteGenealogyRepository extends RemoteRepository
    implements GraphSourceRepository {
  InviteGenealogyRepository({
    required super.remoteApiService,
    required super.log,
  });

  Future<InviteGenealogyGraph> fetchGenealogyBootstrap({String? targetId}) =>
      targetId == null
      ? _fetchOwnAncestors()
      : _fetchAncestorsBetween(targetId);

  Future<InviteGenealogyGraph> _fetchOwnAncestors() async {
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
                : (node.user! as UserPublicModel).toEntity(),
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
            descendantUserCreatedAt: _parseDate(
              edge.descendant_user_created_at,
            )!,
            createdAt: _parseDate(edge.created_at)!,
          ),
      ],
    );
  }

  Future<InviteGenealogyGraph> _fetchAncestorsBetween(String targetId) async {
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
                : (node.user! as UserPublicModel).toEntity(),
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
            descendantUserCreatedAt: _parseDate(
              edge.descendant_user_created_at,
            )!,
            createdAt: _parseDate(edge.created_at)!,
          ),
      ],
    );
  }

  Future<InviteGenealogyChildrenPage> fetchChildren({
    required String nodeKey,
    required int limit,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
  }) async {
    final data = await requestDataOnlineOrThrow(
      GInviteGenealogyChildrenReq(
        (b) => b
          ..vars.nodeKey = nodeKey
          ..vars.afterCreatedAt = afterCreatedAt?.toUtc().toIso8601String()
          ..vars.afterNodeKey = afterNodeKey
          ..vars.limit = limit,
      ),
      label: _label,
    );
    final page = data.inviteGenealogyChildren;
    if (page == null) {
      return const (
        nodes: <InviteGenealogyNode>[],
        edges: <InviteGenealogyEdge>[],
      );
    }
    return (
      nodes: [
        for (final node in page.nodes)
          InviteGenealogyNode(
            nodeKey: node.node_key,
            profile: node.user == null
                ? null
                : (node.user! as UserPublicModel).toEntity(),
            deletedAt: _parseDate(node.deleted_at),
            userCreatedAt: _parseDate(node.user_created_at),
          ),
      ],
      edges: [
        for (final edge in page.edges)
          InviteGenealogyEdge(
            ancestorNodeKey: edge.ancestor_node_key,
            descendantNodeKey: edge.descendant_node_key,
            ancestorUserCreatedAt: _parseDate(edge.ancestor_user_created_at)!,
            descendantUserCreatedAt: _parseDate(
              edge.descendant_user_created_at,
            )!,
            createdAt: _parseDate(edge.created_at)!,
          ),
      ],
    );
  }

  Future<Map<String, int>> fetchChildCounts({
    required List<String> nodeKeys,
  }) async {
    final distinctNodeKeys = nodeKeys
        .where((nodeKey) => nodeKey.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (distinctNodeKeys.isEmpty) {
      return const {};
    }
    final data = await requestDataOnlineOrThrow(
      GInviteGenealogyChildCountsReq(
        (b) => b..vars.nodeKeys.replace(distinctNodeKeys),
      ),
      label: _label,
    );
    return {
      for (final row in data.inviteGenealogyChildCounts)
        row.node_key: row.total_children,
    };
  }

  @override
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  }) => throw UnsupportedError(
    'InviteGenealogyRepository only supports fetchGenealogyBootstrap/fetchChildren '
    'via GraphCubit(genealogyMode: true); the generic '
    'GraphSourceRepository.fetch() contract does not apply to genealogy '
    'node keys.',
  );

  static DateTime? _parseDate(String? raw) {
    if (raw == null || raw.isEmpty) {
      return null;
    }
    return DateTime.tryParse(raw);
  }

  static const _label = 'InviteGenealogy';
}
