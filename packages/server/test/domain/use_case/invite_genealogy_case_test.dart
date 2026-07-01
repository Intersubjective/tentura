import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';

import 'package:tentura_server/domain/entity/invite_genealogy_graph_entity.dart';
import 'package:tentura_server/domain/port/invite_genealogy_repository_port.dart';
import 'package:tentura_server/domain/use_case/invite_genealogy_case.dart';
import 'package:tentura_server/env.dart';

class _FakeInviteGenealogyRepository implements InviteGenealogyRepositoryPort {
  String? lastUserId;
  String? lastBetweenViewerId;
  String? lastBetweenTargetId;
  String? lastChildrenNodeKey;
  DateTime? lastChildrenAfterCreatedAt;
  String? lastChildrenAfterNodeKey;
  int? lastChildrenLimit;
  List<String>? lastChildCountNodeKeys;

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

  @override
  Future<InviteGenealogyGraphEntity> fetchLineageBetween({
    required String viewerId,
    required String targetId,
  }) async {
    lastBetweenViewerId = viewerId;
    lastBetweenTargetId = targetId;
    return const InviteGenealogyGraphEntity(
      viewerNodeKey: 'Gviewer',
      targetNodeKey: 'Gtarget',
      nodes: [],
      edges: [],
    );
  }

  @override
  Future<InviteGenealogyChildrenPageEntity> fetchChildren({
    required String nodeKey,
    required int limit,
    DateTime? afterCreatedAt,
    String? afterNodeKey,
  }) async {
    lastChildrenNodeKey = nodeKey;
    lastChildrenAfterCreatedAt = afterCreatedAt;
    lastChildrenAfterNodeKey = afterNodeKey;
    lastChildrenLimit = limit;
    return const InviteGenealogyChildrenPageEntity(nodes: [], edges: []);
  }

  @override
  Future<Map<String, int>> fetchChildCounts({
    required List<String> nodeKeys,
  }) async {
    lastChildCountNodeKeys = nodeKeys;
    return {for (final nodeKey in nodeKeys) nodeKey: nodeKey.length};
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

  test('fetchLineageBetween delegates viewer and target', () async {
    const targetId = 'Utarget1';
    final result = await case_.fetchLineageBetween(
      viewerId: viewerId,
      targetId: targetId,
    );
    expect(result.targetNodeKey, 'Gtarget');
    expect(repo.lastBetweenViewerId, viewerId);
    expect(repo.lastBetweenTargetId, targetId);
  });

  test('fetchChildren delegates node key, cursor and limit', () async {
    final afterCreatedAt = DateTime.utc(2026, 2);
    final result = await case_.fetchChildren(
      nodeKey: 'Gnode',
      afterCreatedAt: afterCreatedAt,
      afterNodeKey: 'Gafter',
      limit: 10,
    );
    expect(result.edges, isEmpty);
    expect(repo.lastChildrenNodeKey, 'Gnode');
    expect(repo.lastChildrenAfterCreatedAt, afterCreatedAt);
    expect(repo.lastChildrenAfterNodeKey, 'Gafter');
    expect(repo.lastChildrenLimit, 10);
  });

  test('fetchChildCounts delegates node keys to repository', () async {
    final result = await case_.fetchChildCounts(
      nodeKeys: ['Gparent', 'Gchild'],
    );

    expect(result, {'Gparent': 7, 'Gchild': 6});
    expect(repo.lastChildCountNodeKeys, ['Gparent', 'Gchild']);
  });
}
