import 'package:test/test.dart';

import 'package:tentura_server/domain/trust/forward/forward_causal_graph_builder.dart';
import 'package:tentura_server/domain/trust/forward/forward_mass_propagator.dart';
import 'package:tentura_server/domain/trust/forward/forward_provenance.dart';

void main() {
  ForwardProvenanceEdge edge({
    required String id,
    required String sender,
    required String recipient,
    String? parent,
    String? batchId,
  }) =>
      ForwardProvenanceEdge(
        id: id,
        senderId: sender,
        recipientId: recipient,
        createdAt: DateTime.utc(2026, 1, int.parse(id)),
        parentEdgeId: parent,
        batchId: batchId ?? 'B$id',
      );

  EligibleForwardDag linearDag() {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B'),
      edge(id: '2', sender: 'B', recipient: 'C', parent: '1'),
      edge(id: '3', sender: 'C', recipient: 'D', parent: '2'),
    ];
    return EligibleForwardDag(edges: edges, committerId: 'D');
  }

  test('terminal seeding splits unit mass equally across distinct senders', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'D'),
      edge(id: '2', sender: 'B', recipient: 'D'),
    ];
    final dag = EligibleForwardDag(edges: edges, committerId: 'D');
    final raw = ForwardMassPropagator().propagate(
      dag: dag,
      attributionsByBatchId: const {},
    );
    expect(raw[('A', 'D')], closeTo(0.5, 1e-9));
    expect(raw[('B', 'D')], closeTo(0.5, 1e-9));
    expect(
      raw.values.fold<double>(0, (a, b) => a + b),
      closeTo(1.0, 1e-9),
    );
  });

  test('explicit attribution overrides equal fallback', () {
    final edges = [
      edge(id: '1', sender: 'A', recipient: 'B', batchId: 'BA'),
      edge(id: '2', sender: 'B', recipient: 'D', parent: '1', batchId: 'BX'),
    ];
    final dag = EligibleForwardDag(edges: edges, committerId: 'D');
    final raw = ForwardMassPropagator().propagate(
      dag: dag,
      attributionsByBatchId: {
        'BX': [
          ForwardAttributionInput(
            batchId: 'BX',
            parentForwardEdgeId: '1',
            weight: 1.0,
          ),
        ],
      },
    );
    expect(raw[('A', 'B')], closeTo(1.0, 1e-9));
    expect(raw[('B', 'D')], closeTo(1.0, 1e-9));
  });

  test('masses stay within [0, 1]', () {
    final raw = ForwardMassPropagator().propagate(
      dag: linearDag(),
      attributionsByBatchId: const {},
    );
    for (final mass in raw.values) {
      expect(mass, inInclusiveRange(0, 1));
    }
  });
}
