import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_server/domain/entity/forward_candidate_context.dart';
import 'package:tentura_server/domain/entity/forward_candidate_graph_snapshot.dart';
import 'package:tentura_server/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura_server/domain/use_case/forward_candidate_context_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  Future<ForwardCandidateContext> load(List<ForwardCandidateGraphEdge> edges) =>
      ForwardCandidateContextCase(
        _SnapshotRepository(edges),
        env: Env(environment: Environment.test),
        logger: Logger('DirectedCandidatePathTest'),
      ).load(viewerId: 'viewer', candidateId: 'candidate', context: 'personal');

  test(
    'candidate path follows outgoing trust instead of a reverse shortcut',
    () async {
      final result = await load(const [
        ForwardCandidateGraphEdge('viewer', 'z-person'),
        ForwardCandidateGraphEdge('z-person', 'candidate'),
        ForwardCandidateGraphEdge('candidate', 'a-person'),
        ForwardCandidateGraphEdge('a-person', 'viewer'),
      ]);
      expect(result.status, ForwardCandidateContextStatus.path);
      expect(result.nodes.map((node) => node.id), [
        'viewer',
        'z-person',
        'candidate',
      ]);
    },
  );

  test(
    'candidate reachable only against trust direction has longPath status',
    () async {
      final result = await load(const [
        ForwardCandidateGraphEdge('candidate', 'a-person'),
        ForwardCandidateGraphEdge('a-person', 'viewer'),
      ]);
      expect(result.status, ForwardCandidateContextStatus.longPath);
      expect(result.nodes, isEmpty);
    },
  );

  test('trust cycle paths follow outgoing edges for every candidate', () async {
    final useCase = ForwardCandidateContextCase(
      _SnapshotRepository(const [
        ForwardCandidateGraphEdge('V', 'A'),
        ForwardCandidateGraphEdge('A', 'C'),
        ForwardCandidateGraphEdge('C', 'B'),
        ForwardCandidateGraphEdge('B', 'V'),
      ]),
      env: Env(environment: Environment.test),
      logger: Logger('DirectedTrustCycleTest'),
    );
    final candidateC = await useCase.load(
      viewerId: 'V',
      candidateId: 'C',
      context: 'personal',
    );
    expect(candidateC.status, ForwardCandidateContextStatus.path);
    expect(candidateC.nodes.map((node) => node.id), ['V', 'A', 'C']);
    // The same directed topology must also reject the reverse V -> B shortcut.
    final candidateB = await useCase.load(
      viewerId: 'V',
      candidateId: 'B',
      context: 'personal',
    );
    expect(candidateB.status, ForwardCandidateContextStatus.path);
    expect(candidateB.nodes.map((node) => node.id), ['V', 'A', 'C', 'B']);
  });
}

final class _SnapshotRepository
    implements ForwardCandidateContextRepositoryPort {
  _SnapshotRepository(this.edges);
  final List<ForwardCandidateGraphEdge> edges;

  @override
  Future<ForwardCandidateGraphSnapshot> loadSnapshot({
    required String viewerId,
    required String candidateId,
    required String context,
  }) async => ForwardCandidateGraphSnapshot(
    candidateEligible: true,
    edges: edges,
    people: {
      for (final id in {
        for (final edge in edges) ...[edge.a, edge.b],
      })
        id: ForwardCandidatePersonProjection(id: id, displayName: id),
    },
  );
}
