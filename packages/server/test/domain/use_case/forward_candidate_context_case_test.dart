import 'package:injectable/injectable.dart' show Environment;
import 'package:logging/logging.dart';
import 'package:test/test.dart';
import 'package:tentura_server/domain/entity/forward_candidate_context.dart';
import 'package:tentura_server/domain/entity/forward_candidate_graph_snapshot.dart';
import 'package:tentura_server/domain/port/forward_candidate_context_repository_port.dart';
import 'package:tentura_server/domain/use_case/forward_candidate_context_case.dart';
import 'package:tentura_server/env.dart';

void main() {
  late _SnapshotRepository repository;
  late ForwardCandidateContextCase useCase;

  setUp(() {
    repository = _SnapshotRepository();
    useCase = ForwardCandidateContextCase(
      repository,
      env: Env(environment: Environment.test),
      logger: Logger('ForwardCandidateContextCaseTest'),
    );
  });

  test('chooses deterministically after sorting adjacent IDs', () async {
    repository.snapshot = _snapshot(
      edges: const [
        ForwardCandidateGraphEdge('viewer', 'z-person'),
        ForwardCandidateGraphEdge('z-person', 'candidate'),
        ForwardCandidateGraphEdge('viewer', 'a-person'),
        ForwardCandidateGraphEdge('a-person', 'candidate'),
      ],
    );

    final result = await _load(useCase);

    expect(result.status, ForwardCandidateContextStatus.path);
    expect(
      result.nodes.map((node) => node.id),
      ['viewer', 'a-person', 'candidate'],
    );
  });

  test('handles cycles and preserves endpoint order', () async {
    repository.snapshot = _snapshot(
      edges: const [
        ForwardCandidateGraphEdge('person-b', 'viewer'),
        ForwardCandidateGraphEdge('person-a', 'person-b'),
        ForwardCandidateGraphEdge('viewer', 'person-a'),
        ForwardCandidateGraphEdge('person-b', 'candidate'),
      ],
    );

    final result = await _load(useCase);

    expect(result.nodes.first.kind, ForwardCandidateConnectionNodeKind.viewer);
    expect(result.nodes.first.id, 'viewer');
    expect(
      result.nodes.last.kind,
      ForwardCandidateConnectionNodeKind.candidate,
    );
    expect(result.nodes.last.id, 'candidate');
    for (var index = 1; index < result.nodes.length; index++) {
      final pair = {result.nodes[index - 1].id, result.nodes[index].id};
      expect(
        repository.snapshot.edges.any(
          (edge) => pair.containsAll([edge.a, edge.b]),
        ),
        isTrue,
      );
    }
  });

  test('returns bounded-snapshot fallback when route is unresolved', () async {
    repository.snapshot = _snapshot(
      edges: const [ForwardCandidateGraphEdge('viewer', 'person-a')],
    );

    final result = await _load(useCase);

    expect(result.status, ForwardCandidateContextStatus.longPath);
    expect(result.nodes, isEmpty);
  });

  test('returns generic unavailable for an ineligible candidate', () async {
    repository.snapshot = const ForwardCandidateGraphSnapshot.unavailable();

    final result = await _load(useCase);

    expect(result.status, ForwardCandidateContextStatus.unavailable);
    expect(result.nodes, isEmpty);
  });

  test('does not expose an unhydrated intermediary identity', () async {
    repository.snapshot = ForwardCandidateGraphSnapshot(
      candidateEligible: true,
      edges: const [
        ForwardCandidateGraphEdge('viewer', 'deleted-person'),
        ForwardCandidateGraphEdge('deleted-person', 'candidate'),
      ],
      people: const {
        'viewer': ForwardCandidatePersonProjection(
          id: 'viewer',
          displayName: 'You',
        ),
        'candidate': ForwardCandidatePersonProjection(
          id: 'candidate',
          displayName: 'Candidate',
        ),
      },
    );

    final result = await _load(useCase);
    final intermediary = result.nodes[1];

    expect(
      intermediary.kind,
      ForwardCandidateConnectionNodeKind.unavailable,
    );
    expect(intermediary.id, isNull);
    expect(intermediary.displayName, isNull);
  });
}

Future<ForwardCandidateContext> _load(ForwardCandidateContextCase useCase) =>
    useCase.load(
      viewerId: 'viewer',
      candidateId: 'candidate',
      context: 'personal',
    );

ForwardCandidateGraphSnapshot _snapshot({
  required List<ForwardCandidateGraphEdge> edges,
}) => ForwardCandidateGraphSnapshot(
  candidateEligible: true,
  edges: edges,
  people: const {
    'viewer': ForwardCandidatePersonProjection(
      id: 'viewer',
      displayName: 'You',
    ),
    'a-person': ForwardCandidatePersonProjection(
      id: 'a-person',
      displayName: 'A',
    ),
    'z-person': ForwardCandidatePersonProjection(
      id: 'z-person',
      displayName: 'Z',
    ),
    'person-a': ForwardCandidatePersonProjection(
      id: 'person-a',
      displayName: 'A',
    ),
    'person-b': ForwardCandidatePersonProjection(
      id: 'person-b',
      displayName: 'B',
    ),
    'candidate': ForwardCandidatePersonProjection(
      id: 'candidate',
      displayName: 'Candidate',
    ),
  },
);

final class _SnapshotRepository
    implements ForwardCandidateContextRepositoryPort {
  ForwardCandidateGraphSnapshot snapshot =
      const ForwardCandidateGraphSnapshot.unavailable();

  @override
  Future<ForwardCandidateGraphSnapshot> loadSnapshot({
    required String viewerId,
    required String candidateId,
    required String context,
  }) async => snapshot;
}
