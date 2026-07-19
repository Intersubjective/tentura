import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_causal_graph_builder.dart';
import 'package:tentura_server/domain/trust/forward/forward_provenance.dart';

void main() {
  final author = 'A';
  final committer = 'D';
  final commitmentAt = DateTime.utc(2026, 1, 10);

  ForwardProvenanceEdge edge({
    required String id,
    required String sender,
    required String recipient,
    String? parent,
    DateTime? createdAt,
  }) {
    final day = int.parse(id);
    return ForwardProvenanceEdge(
      id: id,
      senderId: sender,
      recipientId: recipient,
      createdAt: createdAt ?? DateTime.utc(2026, 1, day),
      parentEdgeId: parent,
      batchId: 'B$id',
    );
  }

  test('linear chain reaches committer', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B'),
      edge(id: '2', sender: 'B', recipient: 'C', parent: '1'),
      edge(id: '3', sender: 'C', recipient: 'D', parent: '2'),
    ];
    final dag = ForwardCausalGraphBuilder().build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
    );
    expect(dag, isNotNull);
    expect(dag!.edges.length, 3);
  });

  test('rootless non-author edge is rejected', () {
    final stats = ForwardCausalBuildStats();
    final edges = [
      edge(id: '1', sender: 'X', recipient: 'D'),
    ];
    final dag = ForwardCausalGraphBuilder().build(
      authorId: author,
      committerId: committer,
      commitmentAt: commitmentAt,
      allEdges: edges,
      stats: stats,
    );
    expect(dag, isNull);
    expect(stats.rootlessEdgeCount, 1);
  });
}
