import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/invite_genealogy_graph_entity.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/invite_genealogy_case.dart';
import 'package:tentura_server/env.dart';

class _FakeInviteGenealogyRepository implements InviteGenealogyRepositoryPort {
  String? lastUserId;

  @override
  Future<void> recordSignupEdge({
    required String ancestorUserId,
    required DateTime ancestorUserCreatedAt,
    required String descendantUserId,
    required DateTime descendantUserCreatedAt,
    required String invitationId,
  }) async {}

  @override
  Future<InviteGenealogyGraphEntity> fetchLineage({
    required String userId,
  }) async {
    lastUserId = userId;
    return const InviteGenealogyGraphEntity(
      viewerNodeKey: 'Gviewer',
      nodes: [],
      edges: [],
    );
  }
}

void main() {
  late _FakeInviteGenealogyRepository repo;
  late InviteGenealogyCase case_;

  const viewerId = 'Uviewer1';

  setUp(() {
    repo = _FakeInviteGenealogyRepository();
    case_ = InviteGenealogyCase(
      repo,
      env: Env(environment: Environment.test),
      logger: Logger('InviteGenealogyCaseTest'),
    );
  });

  test('fetchLineage delegates to repository', () async {
    final result = await case_.fetchLineage(viewerId: viewerId);
    expect(result.viewerNodeKey, 'Gviewer');
    expect(repo.lastUserId, viewerId);
  });
}
