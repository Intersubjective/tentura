import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:logging/logging.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/env.dart';
import 'package:tentura/features/inbox/domain/entity/post_summary.dart';
import 'package:tentura/features/inbox/domain/port/posts_repository_port.dart';
import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';

final class _EmptyPostsRepository implements PostsRepositoryPort {
  @override
  Future<List<PostSummary>> myPosts() async => const [];

  @override
  Future<PostSummary?> postSummary(String id) async => null;
}

/// Supplies the conversation list for Activity screen tests focused on its feed.
void registerNoopPostsCase(RealtimeSyncCase realtimeSync) {
  GetIt.I.registerSingleton<PostsCase>(
    PostsCase(
      _EmptyPostsRepository(),
      realtimeSync,
      env: const Env(),
      logger: Logger('empty-posts-test'),
    ),
  );
  addTearDown(() {
    if (GetIt.I.isRegistered<PostsCase>()) {
      GetIt.I.unregister<PostsCase>();
    }
  });
}
