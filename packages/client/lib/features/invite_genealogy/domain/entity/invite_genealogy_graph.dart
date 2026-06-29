import 'package:tentura/domain/entity/profile.dart';

class InviteGenealogyGraph {
  const InviteGenealogyGraph({
    required this.viewerNodeKey,
    required this.nodes,
    required this.edges,
  });

  final String viewerNodeKey;
  final List<InviteGenealogyNode> nodes;
  final List<InviteGenealogyEdge> edges;
}

class InviteGenealogyNode {
  const InviteGenealogyNode({
    required this.nodeKey,
    this.profile,
    this.deletedAt,
    this.userCreatedAt,
  });

  final String nodeKey;
  final Profile? profile;
  final DateTime? deletedAt;
  final DateTime? userCreatedAt;

  bool get isDeleted => deletedAt != null || profile == null;
}

class InviteGenealogyEdge {
  const InviteGenealogyEdge({
    required this.ancestorNodeKey,
    required this.descendantNodeKey,
    required this.ancestorUserCreatedAt,
    required this.descendantUserCreatedAt,
    required this.createdAt,
  });

  final String ancestorNodeKey;
  final String descendantNodeKey;
  final DateTime ancestorUserCreatedAt;
  final DateTime descendantUserCreatedAt;
  final DateTime createdAt;
}
