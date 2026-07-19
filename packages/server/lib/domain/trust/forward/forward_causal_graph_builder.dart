import 'forward_graph_integrity_exception.dart';
import 'forward_provenance.dart';

final class ForwardCausalBuildStats {
  ForwardCausalBuildStats({this.rootlessEdgeCount = 0});

  int rootlessEdgeCount;
}

final class EligibleForwardDag {
  const EligibleForwardDag({
    required this.edges,
    required this.committerId,
  });

  final List<ForwardProvenanceEdge> edges;
  final String committerId;

  Set<(String, String)> get pairs => {
    for (final e in edges) (e.senderId, e.recipientId),
  };
}

/// Builds author-rooted eligible forward DAGs reaching a committer.
final class ForwardCausalGraphBuilder {
  EligibleForwardDag? build({
    required String authorId,
    required String committerId,
    required DateTime commitmentAt,
    required List<ForwardProvenanceEdge> allEdges,
    ForwardCausalBuildStats? stats,
  }) {
    final edgeById = {for (final e in allEdges) e.id: e};
    final eligible = <ForwardProvenanceEdge>[];

    bool isEligible(ForwardProvenanceEdge e) {
      if (!e.createdAt.isBefore(commitmentAt)) return false;
      if (e.cancelledAt != null && e.cancelledAt!.isBefore(commitmentAt)) {
        return false;
      }
      final parentId = e.parentEdgeId;
      if (parentId == null) {
        if (e.senderId != authorId) {
          stats?.rootlessEdgeCount++;
          return false;
        }
        return true;
      }
      final parent = edgeById[parentId];
      if (parent == null) return false;
      if (!parent.createdAt.isBefore(e.createdAt)) return false;
      if (parent.recipientId != e.senderId) return false;
      return isEligible(parent);
    }

    for (final e in allEdges) {
      if (!isEligible(e)) continue;
      eligible.add(e);
    }

    final reachable = _reachableToCommitter(
      committerId: committerId,
      edges: eligible,
    );
    if (reachable.isEmpty) return null;

    final dagEdges = eligible.where((e) => reachable.contains(e.id)).toList();
    if (_hasIntegrityFailure(dagEdges, committerId)) {
      throw ForwardGraphIntegrityException(committerId);
    }
    return EligibleForwardDag(edges: dagEdges, committerId: committerId);
  }

  Set<String> _reachableToCommitter({
    required String committerId,
    required List<ForwardProvenanceEdge> edges,
  }) {
    final inbound = <String, List<ForwardProvenanceEdge>>{};
    for (final e in edges) {
      inbound.putIfAbsent(e.recipientId, () => []).add(e);
    }

    final reachableEdgeIds = <String>{};
    final queue = <String>[committerId];
    final visitedNodes = <String>{committerId};

    while (queue.isNotEmpty) {
      final node = queue.removeAt(0);
      for (final e in inbound[node] ?? const []) {
        reachableEdgeIds.add(e.id);
        if (visitedNodes.add(e.senderId)) {
          queue.add(e.senderId);
        }
      }
    }
    return reachableEdgeIds;
  }

  bool _hasIntegrityFailure(
    List<ForwardProvenanceEdge> edges,
    String committerId,
  ) {
    if (edges.isEmpty) return false;
    final inbound = <String, List<ForwardProvenanceEdge>>{};
    for (final e in edges) {
      inbound.putIfAbsent(e.recipientId, () => []).add(e);
    }

    var failed = false;
    void visit(String node, Set<String> stack) {
      if (failed) return;
      if (!stack.add(node)) {
        failed = true;
        return;
      }
      for (final e in inbound[node] ?? const []) {
        visit(e.senderId, stack);
      }
      stack.remove(node);
    }

    visit(committerId, {});
    return failed;
  }
}
