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
      edge(id: '1', sender: 'A', recipient: 'B', createdAt: DateTime.utc(2026, 1, 5)),
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
}
