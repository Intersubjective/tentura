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
    if (ids == null) return const ForwardCandidateContext.longPath();

    return ForwardCandidateContext(
      status: ForwardCandidateContextStatus.path,
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
  final adjacent = <String, Set<String>>{};
  for (final edge in edges) {
    if (edge.a.isEmpty || edge.b.isEmpty || edge.a == edge.b) continue;
    adjacent.putIfAbsent(edge.a, () => <String>{}).add(edge.b);
    adjacent.putIfAbsent(edge.b, () => <String>{}).add(edge.a);
  }

  final queue = Queue<String>()..add(viewerId);
  final visited = <String>{viewerId};
  final parent = <String, String>{};

  while (queue.isNotEmpty) {
    final current = queue.removeFirst();
    final neighbors = adjacent[current]?.toList() ?? const <String>[];
    neighbors.sort();
    for (final neighbor in neighbors) {
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
