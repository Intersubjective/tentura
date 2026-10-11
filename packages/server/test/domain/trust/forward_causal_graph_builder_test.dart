import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_causal_graph_builder.dart';
import 'package:tentura_server/domain/trust/forward/forward_graph_integrity_exception.dart';
import 'package:tentura_server/domain/trust/forward/forward_provenance.dart';

void main() {
  const author = 'A';
  const committer = 'D';
  final commitmentAt = DateTime.utc(2026, 1, 10);

  ForwardProvenanceEdge edge({
    required String id,
    required String sender,
    required String recipient,
    String? parent,
    DateTime? createdAt,
    DateTime? cancelledAt,
  }) {
    final day = int.parse(id);
    return ForwardProvenanceEdge(
      id: id,
      senderId: sender,
      recipientId: recipient,
      createdAt: createdAt ?? DateTime.utc(2026, 1, day),
      parentEdgeId: parent,
      batchId: 'B$id',
      cancelledAt: cancelledAt,
    );
  }

  final builder = ForwardCausalGraphBuilder();

  test('linear chain reaches committer', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B'),
      edge(id: '2', sender: 'B', recipient: 'C', parent: '1'),
      edge(id: '3', sender: 'C', recipient: 'D', parent: '2'),
    ];
    final dag = builder.build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
    );
    expect(dag, isNotNull);
    expect(dag!.edges.length, 3);
  });

  test('diamond merge keeps both paths to committer', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B'),
      edge(id: '2', sender: 'A', recipient: 'C'),
      edge(id: '3', sender: 'B', recipient: 'D', parent: '1'),
      edge(id: '4', sender: 'C', recipient: 'D', parent: '2'),
    ];
    final dag = builder.build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
    );
    expect(dag, isNotNull);
    expect(dag!.edges.length, 4);
    expect(dag.pairs, {
      ('A', 'B'),
      ('A', 'C'),
      ('B', 'D'),
      ('C', 'D'),
    });
  });

  test('shared stem with split then merge', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B'),
      edge(id: '2', sender: 'B', recipient: 'C', parent: '1'),
      edge(id: '3', sender: 'B', recipient: 'E', parent: '1'),
      edge(id: '4', sender: 'C', recipient: 'D', parent: '2'),
      edge(id: '5', sender: 'E', recipient: 'D', parent: '3'),
    ];
    final dag = builder.build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
    );
    expect(dag, isNotNull);
    expect(dag!.edges.length, 5);
  });

  test('rootless non-author edge is rejected and counted in BuildStats', () {
    final stats = ForwardCausalBuildStats();
    final edges = [
      edge(id: '1', sender: 'X', recipient: 'D'),
    ];
    final dag = builder.build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
      stats: stats,
    );
    expect(dag, isNull);
    expect(stats.rootlessEdgeCount, 1);
  });

  test('late edge at or after commitment is ignored', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'D'),
      edge(
        id: '2',
        sender: 'A',
        recipient: 'B',
        createdAt: commitmentAt,
      ),
    ];
    final dag = builder.build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
    );
    expect(dag, isNotNull);
    expect(dag!.edges.map((e) => e.id), ['1']);
  });

  test('cancelled before commitment is ignored', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B'),
      edge(
        id: '2',
        sender: 'B',
        recipient: 'D',
        parent: '1',
        cancelledAt: DateTime.utc(2026, 1, 5),
      ),
    ];
    final dag = builder.build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
    );
    expect(dag, isNull);
  });

  test('parent recipient mismatch rejects child edge', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B'),
      edge(id: '2', sender: 'C', recipient: 'D', parent: '1'),
    ];
    final dag = builder.build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
    );
    expect(dag, isNull);
  });

  test('temporal order violation rejects child edge', () {
    final edges = [
      edge(
        id: '1',
        sender: 'A',
        recipient: 'B',
        createdAt: DateTime.utc(2026, 1, 5),
      ),
      edge(
        id: '2',
        sender: 'B',
        recipient: 'D',
        parent: '1',
        createdAt: DateTime.utc(2026, 1, 4),
      ),
    ];
    final dag = builder.build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
    );
    expect(dag, isNull);
  });

  test('synthetic cycle throws ForwardGraphIntegrityException', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B'),
      edge(id: '2', sender: 'B', recipient: 'C', parent: '1'),
      edge(id: '3', sender: 'C', recipient: 'B', parent: '2'),
      edge(id: '4', sender: 'B', recipient: 'D', parent: '3'),
    ];
    expect(
      () => builder.build(
        authorId: author,
        committerId: committer,
        commitmentAt: commitmentAt,
        allEdges: edges,
      ),
      throwsA(isA<ForwardGraphIntegrityException>()),
    );
  });

  group('extra segments (budding C7)', () {
    // The Post chain P→Q→D (rooted at the Post author P) next to the child
    // delivery edge A→D.
    final cutoff = DateTime.utc(2026, 1, 5);
    List<ForwardProvenanceEdge> postChain() => [
      edge(id: '1', sender: 'P', recipient: 'Q'),
      edge(id: '2', sender: 'Q', recipient: 'D', parent: '1'),
    ];

    EligibleForwardDag? buildWith(
      List<ForwardProvenanceEdge> segmentEdges, {
      String rootSenderId = 'P',
      DateTime? cutoffAt,
    }) => builder.build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: [edge(id: '3', sender: 'A', recipient: 'D')],
      extraSegments: [
        ForwardRoutingSegment(
          edges: segmentEdges,
          attributionByBatch: const {},
          rootSenderId: rootSenderId,
          cutoffAt: cutoffAt ?? cutoff,
        ),
      ],
    );

    test('a segment root is accepted when it is the segment root sender', () {
      final dag = buildWith(postChain());
      expect(dag, isNotNull);
      expect(dag!.edges.map((e) => e.id).toSet(), {'1', '2', '3'});
      expect(dag.segmentOf('3'), 0);
      expect(dag.segmentOf('1'), 1);
      expect(dag.segmentOf('2'), 1);
    });

    test('a segment rooted at anyone else is dropped', () {
      final dag = buildWith(postChain(), rootSenderId: 'X');
      expect(dag!.edges.map((e) => e.id).toSet(), {'3'});
    });

    test('segment edges at or after the cutoff are dropped', () {
      final dag = buildWith(postChain(), cutoffAt: DateTime.utc(2026, 1, 2));
      expect(dag!.edges.map((e) => e.id).toSet(), {'3'});
    });

    test('a segment edge cancelled before the cutoff drops the chain', () {
      final dag = buildWith([
        edge(id: '1', sender: 'P', recipient: 'Q'),
        edge(
          id: '2',
          sender: 'Q',
          recipient: 'D',
          parent: '1',
          cancelledAt: DateTime.utc(2026, 1, 4),
        ),
      ]);
      expect(dag!.edges.map((e) => e.id).toSet(), {'3'});
    });

    test('a segment alone reaches the committer', () {
      final dag = builder.build(
        authorId: author,
        committerId: committer,
        commitmentAt: commitmentAt,
        allEdges: const [],
        extraSegments: [
          ForwardRoutingSegment(
            edges: postChain(),
            attributionByBatch: const {},
            rootSenderId: 'P',
            cutoffAt: cutoff,
          ),
        ],
      );
      expect(dag!.edges.map((e) => e.id).toSet(), {'1', '2'});
    });
  });
}
