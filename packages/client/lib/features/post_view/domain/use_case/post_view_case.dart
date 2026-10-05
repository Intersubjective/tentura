import 'package:tentura/features/forward/data/repository/forward_repository.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';

/// What the Post screen shows besides the beacon itself.
class PostViewCase {
  PostViewCase(this._posts, this._forwards);

  final PostsRepositoryPort _posts;
  final ForwardRepository _forwards;

  /// The viewer's conversation row for [beaconId] (root excerpt, pin, mute
  /// expiry); null when the viewer is not in the conversation.
  Future<PostSummary?> summaryOf(String beaconId) =>
      _posts.postSummary(beaconId);

  /// Every forward of [beaconId] the viewer may see: who brought whom in.
  Future<List<ForwardEdge>> forwardEdges(String beaconId) =>
      _forwards.fetchEdges(beaconId: beaconId);

  /// The latest of [edges] addressed to [viewerId], if any.
  static ForwardEdge? latestTo(List<ForwardEdge> edges, String viewerId) {
    ForwardEdge? latest;
    for (final e in edges) {
      if (e.recipient.id != viewerId) continue;
      if (latest == null || e.createdAt.isAfter(latest.createdAt)) latest = e;
    }
    return latest;
  }
}
