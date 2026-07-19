import 'forward_causal_graph_builder.dart';
import 'forward_provenance.dart';

typedef ForwardPair = (String sender, String recipient);

/// Backward terminal-mass propagation through an eligible DAG.
final class ForwardMassPropagator {
  Map<ForwardPair, double> propagate({
    required EligibleForwardDag dag,
    required Map<String, List<ForwardAttributionInput>> attributionsByBatchId,
  }) {
    final edges = dag.edges;
    final inbound = <String, List<ForwardProvenanceEdge>>{};
    for (final e in edges) {
      inbound.putIfAbsent(e.recipientId, () => []).add(e);
    }

    final raw = <ForwardPair, double>{};

    void distribute({
      required String recipient,
      required double mass,
      String? downstreamBatchId,
    }) {
      final incoming = inbound[recipient];
      if (incoming == null || incoming.isEmpty) return;

      final weights = recipient == dag.committerId
          ? _terminalWeights(incoming)
          : _attributedWeights(
              incoming: incoming,
              batchId: downstreamBatchId,
              attributionsByBatchId: attributionsByBatchId,
            );

      for (final e in incoming) {
        final w = weights[e.id] ?? 0;
        if (w <= 0) continue;
        final edgeMass = mass * w;
        final key = (e.senderId, e.recipientId);
        raw[key] = (raw[key] ?? 0) + edgeMass;
        distribute(
          recipient: e.senderId,
          mass: edgeMass,
          downstreamBatchId: e.batchId,
        );
      }
    }

    distribute(recipient: dag.committerId, mass: 1.0);
    return raw;
  }

  Map<String, double> _terminalWeights(
    List<ForwardProvenanceEdge> incoming,
  ) {
    final bySender = <String, List<ForwardProvenanceEdge>>{};
    for (final e in incoming) {
      bySender.putIfAbsent(e.senderId, () => []).add(e);
    }
    final senderWeight = 1.0 / bySender.length;
    final weights = <String, double>{};
    for (final entry in bySender.entries) {
      final perEdge = senderWeight / entry.value.length;
      for (final e in entry.value) {
        weights[e.id] = perEdge;
      }
    }
    return weights;
  }

  Map<String, double> _attributedWeights({
    required List<ForwardProvenanceEdge> incoming,
    required String? batchId,
    required Map<String, List<ForwardAttributionInput>> attributionsByBatchId,
  }) {
    if (batchId != null) {
      final attrs = attributionsByBatchId[batchId];
      if (attrs != null && attrs.isNotEmpty) {
        final weights = <String, double>{};
        for (final attr in attrs) {
          if (incoming.any((e) => e.id == attr.parentForwardEdgeId)) {
            weights[attr.parentForwardEdgeId] = attr.weight;
          }
        }
        if (weights.isNotEmpty) {
          final sum = weights.values.fold<double>(0, (a, b) => a + b);
          if (sum > 0) {
            return {
              for (final e in incoming)
                e.id: (weights[e.id] ?? 0) / sum,
            };
          }
        }
      }
    }
    return _terminalWeights(incoming);
  }
}
