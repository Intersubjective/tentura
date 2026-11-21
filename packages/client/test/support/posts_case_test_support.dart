import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';

PostsCase buildTestPostsCase(
  PostsRepositoryPort repository,
  RealtimeSyncCase realtimeSync,
) => PostsCase(repository, realtimeSync);
