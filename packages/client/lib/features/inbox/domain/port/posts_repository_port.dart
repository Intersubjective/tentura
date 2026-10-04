import '../entity/post_summary.dart';

abstract interface class PostsRepositoryPort {
  /// Every Post the viewer is in; ordering and grouping are the caller's.
  Future<List<PostSummary>> myPosts();
}
