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
    this.segmentByEdgeId = const {},
  });

  final List<ForwardProvenanceEdge> edges;
  final String committerId;

  /// Edge id → segment index: 0 is the Request's own graph, `i + 1` is
  /// `extraSegments[i]`. Absent ids are 0.
  final Map<String, int> segmentByEdgeId;

  int segmentOf(String edgeId) => segmentByEdgeId[edgeId] ?? 0;

  Set<(String, String)> get pairs => {
    for (final e in edges) (e.senderId, e.recipientId),
  };
}

/// A per-helper causal graph from another beacon (budding C7, Arch §7): the
/// Post chain an invitee arrived through. Its edges are eligible when they
/// are rooted at [rootSenderId] (the Post author) and were created before, and
/// not cancelled before, [cutoffAt] (the child's `published_at`).
final class ForwardRoutingSegment {
  const ForwardRoutingSegment({
    required this.edges,
    required this.attributionByBatch,
    required this.rootSenderId,
    required this.cutoffAt,
  });

  final List<ForwardProvenanceEdge> edges;
  final Map<String, List<ForwardAttributionInput>> attributionByBatch;
  final String rootSenderId;
  final DateTime cutoffAt;
}

/// Builds author-rooted eligible forward DAGs reaching a committer.
final class ForwardCausalGraphBuilder {
  /// The DAG of eligible edges reaching [committerId]: the Request's own
  /// graph ([allEdges], rooted at [authorId], cut at [commitmentAt]) plus each
  /// of [extraSegments] (rooted at its own sender, cut at its own cutoff).
  ///
  /// Segments stay separate graphs that meet only at the committer: each is
  /// reached, checked for cycles and later propagated on its own
  /// ([EligibleForwardDag.segmentOf]).
  EligibleForwardDag? build({
    required String authorId,
    required String committerId,
    required DateTime commitmentAt,
    required List<ForwardProvenanceEdge> allEdges,
    List<ForwardRoutingSegment> extraSegments = const [],
    ForwardCausalBuildStats? stats,
  }) {
    final dagEdges = <ForwardProvenanceEdge>[];
    final segmentByEdgeId = <String, int>{};
    final graphs = [
      (edges: allEdges, rootSenderId: authorId, cutoffAt: commitmentAt),
      for (final s in extraSegments)
        (edges: s.edges, rootSenderId: s.rootSenderId, cutoffAt: s.cutoffAt),
    ];
    for (var i = 0; i < graphs.length; i++) {
      final graph = graphs[i];
      final reached = _reachingEdges(
        rootSenderId: graph.rootSenderId,
        committerId: committerId,
        cutoffAt: graph.cutoffAt,
        allEdges: graph.edges,
        stats: i == 0 ? stats : null,
      );
      for (final e in reached) {
        if (segmentByEdgeId.containsKey(e.id)) continue;
        segmentByEdgeId[e.id] = i;
        dagEdges.add(e);
      }
    }
    if (dagEdges.isEmpty) return null;
    return EligibleForwardDag(
      edges: dagEdges,
      committerId: committerId,
      segmentByEdgeId: {
        for (final entry in segmentByEdgeId.entries)
          if (entry.value != 0) entry.key: entry.value,
      },
    );
  }

  List<ForwardProvenanceEdge> _reachingEdges({
    required String rootSenderId,
    required String committerId,
    required DateTime cutoffAt,
    required List<ForwardProvenanceEdge> allEdges,
    ForwardCausalBuildStats? stats,
  }) {
    final edgeById = {for (final e in allEdges) e.id: e};
    final eligible = <ForwardProvenanceEdge>[];

    bool isEligible(ForwardProvenanceEdge e) {
      if (!e.createdAt.isBefore(cutoffAt)) return false;
      if (e.cancelledAt != null && e.cancelledAt!.isBefore(cutoffAt)) {
        return false;
      }
      final parentId = e.parentEdgeId;
      if (parentId == null) {
        if (e.senderId != rootSenderId) {
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
    if (reachable.isEmpty) return const [];

    final dagEdges = eligible.where((e) => reachable.contains(e.id)).toList();
    if (_hasIntegrityFailure(dagEdges, committerId)) {
      throw ForwardGraphIntegrityException(committerId);
    }
    return dagEdges;
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
      for (final e in inbound[node] ?? const <ForwardProvenanceEdge>[]) {
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
      for (final e in inbound[node] ?? const <ForwardProvenanceEdge>[]) {
        visit(e.senderId, stack);
      }
      stack.remove(node);
    }

    visit(committerId, {});
    return failed;
  }
}
