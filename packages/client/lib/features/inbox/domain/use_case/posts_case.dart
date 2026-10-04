import 'package:injectable/injectable.dart';

import 'package:tentura/domain/entity/realtime/realtime_entity_change.dart';
import 'package:tentura/domain/use_case/realtime_sync_case.dart';
import 'package:tentura/domain/use_case/use_case_base.dart';

import '../entity/post_summary.dart';
import '../port/posts_repository_port.dart';

@singleton
final class PostsCase extends UseCaseBase {
  PostsCase(
    this._repository,
    this._realtimeSyncCase, {
    required super.env,
    required super.logger,
  });

  final PostsRepositoryPort _repository;
  final RealtimeSyncCase _realtimeSyncCase;

  /// Fires on any beacon change: a reply, pin, mute, leave or a newly
  /// addressed Post all show up as one, and the list is cheap to refetch.
  Stream<void> get changes => _realtimeSyncCase
      .changesFor(const {RealtimeEntityKind.beacon})
      .map((_) {});

  Future<List<PostSummary>> myPosts() => _repository.myPosts();
}
