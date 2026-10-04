import 'package:injectable/injectable.dart';

import 'package:tentura/data/service/remote_api_service.dart';

import '../../domain/entity/post_summary.dart';
import '../../domain/port/posts_repository_port.dart';
import '../gql/_g/my_posts.req.gql.dart';

@Singleton(as: PostsRepositoryPort, env: [Environment.dev, Environment.prod])
class PostsRepository implements PostsRepositoryPort {
  const PostsRepository(this._remoteApiService);

  final RemoteApiService _remoteApiService;

  static const _label = 'MyPosts';

  @override
  Future<List<PostSummary>> myPosts() async {
    final rows = await _remoteApiService
        .request(GMyPostsReq())
        .firstWhere((e) => e.dataSource == DataSource.Link)
        .then((r) => r.dataOrThrow(label: _label).myPosts);
    return [
      for (final row in rows)
        PostSummary(
          id: row.id,
          authorId: row.authorId,
          authorName: row.authorName,
          authorAvatar: row.authorAvatar,
          rootExcerpt: row.rootExcerpt ?? '',
          lastMessageExcerpt: row.lastMessageExcerpt,
          lastActivityAt:
              _parse(row.lastActivityAt) ??
              _parse(row.lastMessageAt) ??
              DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
          pinnedAt: _parse(row.pinnedAt),
          mutedUntil: _parse(row.mutedUntil),
          unreadCount: row.unreadCount,
          isAuthor: row.isAuthor,
        ),
    ];
  }

  static DateTime? _parse(String? raw) =>
      raw == null ? null : DateTime.tryParse(raw)?.toUtc();
}
