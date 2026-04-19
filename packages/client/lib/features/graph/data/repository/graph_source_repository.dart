import '../../domain/entity/edge_directed.dart';

// ignore_for_file: one_member_abstracts -- two prod implementations + test mocks

/// Pluggable backend for graph cubit (MeritRank graph vs forwards edges).
abstract class GraphSourceRepository {
  /// Optional viewer id; forwards graph repository uses it to link ego to the
  /// beacon author when they differ.
  Future<Set<EdgeDirected>> fetch({
    bool positiveOnly = true,
    String context = '',
    String? focus,
    int offset = 0,
    int limit = 5,
    String? viewerUserId,
  });
}
