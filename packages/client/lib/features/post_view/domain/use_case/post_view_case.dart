import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';

/// What the Post screen shows besides the beacon itself.
class PostViewCase {
  PostViewCase(this._posts, this._forwards);

  final PostsRepositoryPort _posts;
  final ForwardRepository _forwards;

  /// The viewer's conversation row for [beaconId] (root excerpt, mute expiry).
  Future<PostSummary?> summaryOf(String beaconId) async =>
      (await _posts.myPosts()).where((p) => p.id == beaconId).firstOrNull;

  /// The latest forward of [beaconId] addressed to [viewerId], if any.
  Future<ForwardEdge?> forwardedTo({
    required String beaconId,
    required String viewerId,
  }) async {
    final edges = await _forwards.fetchEdges(beaconId: beaconId);
    ForwardEdge? latest;
    for (final e in edges) {
      if (e.recipient.id != viewerId) continue;
      if (latest == null || e.createdAt.isAfter(latest.createdAt)) latest = e;
    }
    return latest;
  }
}
