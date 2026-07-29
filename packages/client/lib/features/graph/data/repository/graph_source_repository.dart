import '../../domain/entity/edge_directed.dart';

// ignore_for_file: one_member_abstracts -- two prod implementations + test mocks

/// Pluggable backend for graph cubit (MeritRank graph vs forwards edges).
abstract class GraphSourceRepository {
  /// Optional viewer id (GraphCubit passes the signed-in user). MeritRank
  /// graph may use it; forwards graph ignores it.
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  });

  /// Edges whose both endpoints are already known. Sources that have no notion
  /// of a wider graph (forwards, genealogy) return nothing.
  Future<Set<EdgeDirected>> fetchEdgesBetween({
    required Set<String> nodeIds,
    bool positiveOnly = true,
  }) async => const {};
}
