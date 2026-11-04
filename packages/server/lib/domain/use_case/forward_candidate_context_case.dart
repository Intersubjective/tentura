import 'dart:collection';

import 'package:injectable/injectable.dart';
import 'package:tentura_server/domain/entity/forward_candidate_context.dart';
import 'package:tentura_server/domain/entity/forward_candidate_graph_snapshot.dart';
import 'package:tentura_server/domain/port/forward_candidate_context_repository_port.dart';

import '_use_case_base.dart';

/// Builds one deterministic path through an authorized, capped MeritRank
/// snapshot. The result describes provenance only and does not drive candidate
/// recommendation or selection eligibility.
@Singleton(order: 2)
final class ForwardCandidateContextCase extends UseCaseBase {
  ForwardCandidateContextCase(
    this._repository, {
    required super.env,
    required super.logger,
  });

  final ForwardCandidateContextRepositoryPort _repository;

  Future<ForwardCandidateContext> load({
    required String viewerId,
    required String candidateId,
    required String context,
  }) async {
    if (viewerId.trim().isEmpty || candidateId.trim().isEmpty) {
      return const ForwardCandidateContext.unavailable();
    }

    final snapshot = await _repository.loadSnapshot(
      viewerId: viewerId,
      candidateId: candidateId,
      context: context,
    );
    if (!snapshot.candidateEligible) {
      return const ForwardCandidateContext.unavailable();
    }

    final ids = _findPath(
      viewerId: viewerId,
      candidateId: candidateId,
      edges: snapshot.edges,
    );
    if (ids == null) {
      return ForwardCandidateContext.longPath(
        candidateJoinedAt: snapshot.candidateJoinedAt,
      );
    }

    return ForwardCandidateContext(
      status: ForwardCandidateContextStatus.path,
      candidateJoinedAt: snapshot.candidateJoinedAt,
      nodes: [
        for (var index = 0; index < ids.length; index++)
          _toNode(
            id: ids[index],
            index: index,
            lastIndex: ids.length - 1,
            people: snapshot.people,
          ),
      ],
    );
  }
}

List<String>? _findPath({
  required String viewerId,
  required String candidateId,
  required List<ForwardCandidateGraphEdge> edges,
}) {
  final adjacent = <String, List<ForwardCandidateGraphEdge>>{};
  for (final edge in edges) {
    if (edge.a.isEmpty || edge.b.isEmpty || edge.a == edge.b) continue;
    adjacent.putIfAbsent(edge.a, () => []).add(edge);
  }
  // BFS keeps paths shortest. Ordering each outgoing frontier preserves the
  // strongest first hop, then incoming trust and ID at each subsequent hop.
  for (final neighbors in adjacent.values) {
    neighbors.sort((left, right) {
      final byTrust = right.weight.compareTo(left.weight);
      return byTrust != 0 ? byTrust : left.b.compareTo(right.b);
    });
  }

  final queue = Queue<String>()..add(viewerId);
  final visited = <String>{viewerId};
  final parent = <String, String>{};

  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    for (final edge
        in adjacent[current] ?? const <ForwardCandidateGraphEdge>[]) {
      final neighbor = edge.b;
      if (!visited.add(neighbor)) continue;
      parent[neighbor] = current;
      if (neighbor == candidateId) {
        final reversed = <String>[candidateId];
        var cursor = candidateId;
        while (cursor != viewerId) {
          cursor = parent[cursor]!;
          reversed.add(cursor);
        }
        return reversed.reversed.toList(growable: false);
      }
      queue.add(neighbor);
    }
  }
  return null;
}

ForwardCandidateConnectionNode _toNode({
  required String id,
  required int index,
  required int lastIndex,
  required Map<String, ForwardCandidatePersonProjection> people,
}) {
  final person = people[id];
  if (index != 0 && index != lastIndex && person == null) {
    return const ForwardCandidateConnectionNode(
      kind: ForwardCandidateConnectionNodeKind.unavailable,
    );
  }
  return ForwardCandidateConnectionNode(
    kind: index == 0
        ? ForwardCandidateConnectionNodeKind.viewer
        : index == lastIndex
        ? ForwardCandidateConnectionNodeKind.candidate
        : ForwardCandidateConnectionNodeKind.person,
    id: id,
    displayName: person?.displayName,
    image: person?.image,
  );
}
