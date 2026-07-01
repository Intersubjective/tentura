import 'package:tentura_server/domain/entity/invite_genealogy_graph_entity.dart';

abstract class InviteGenealogyRepositoryPort {
  Future<void> recordSignupEdge({
    required String ancestorUserId,
    required DateTime ancestorUserCreatedAt,
    required String descendantUserId,
    required DateTime descendantUserCreatedAt,
    required String invitationId,
  });

  Future<InviteGenealogyGraphEntity> fetchLineage({
    required String userId,
  });

  Future<InviteGenealogyGraphEntity> fetchLineageBetween({
    required String viewerId,
    required String targetId,
  });

  Future<InviteGenealogyChildrenPageEntity> fetchChildren({
    required String nodeKey,
    required int limit,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
  });
}
