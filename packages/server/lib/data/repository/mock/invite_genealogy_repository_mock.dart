import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/invite_genealogy_graph_entity.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';

@Injectable(
  as: InviteGenealogyRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class InviteGenealogyRepositoryMock implements InviteGenealogyRepositoryPort {
  final recordedEdges = <({
    String ancestorUserId,
    DateTime ancestorUserCreatedAt,
    String descendantUserId,
    DateTime descendantUserCreatedAt,
    String invitationId,
  })>[];

  InviteGenealogyGraphEntity lineage = const InviteGenealogyGraphEntity(
    viewerNodeKey: 'Gviewer',
    nodes: [],
    edges: [],
  );

  @override
  Future<void> recordSignupEdge({
    required String ancestorUserId,
    required DateTime ancestorUserCreatedAt,
    required String descendantUserId,
    required DateTime descendantUserCreatedAt,
    required String invitationId,
  }) async {
    recordedEdges.add(
      (
        ancestorUserId: ancestorUserId,
        ancestorUserCreatedAt: ancestorUserCreatedAt,
        descendantUserId: descendantUserId,
        descendantUserCreatedAt: descendantUserCreatedAt,
        invitationId: invitationId,
      ),
    );
  }

  @override
  Future<InviteGenealogyGraphEntity> fetchLineage({
    required String userId,
  }) async =>
      lineage;
}
