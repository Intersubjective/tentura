import 'dart:async';

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
  }) {
    // The list is not mounted on most routes, so a read or a removed Post
    // must refresh the dot on its own.
    // Lives as long as the app-wide singleton.
    _realtimeSyncCase
        .changesFor(const {
          RealtimeEntityKind.roomSeen,
          RealtimeEntityKind.beacon,
        })
        .listen((_) => _refreshWhileUnread());
  }

  final PostsRepositoryPort _repository;
  final RealtimeSyncCase _realtimeSyncCase;

  /// Fires on any beacon change: a reply, pin, mute, leave or a newly
  /// addressed Post all show up as one, and the list is cheap to refetch.
  Stream<void> get changes => _realtimeSyncCase
      .changesFor(const {RealtimeEntityKind.beacon})
      .map((_) {});

  /// Whether any of the viewer's Posts has unread messages, as of the last
  /// [myPosts] load. Feeds the Conversations navigation dot, which also sits
  /// on routes outside Home's providers.
  bool get hasUnread => _hasUnread;
  var _hasUnread = false;

  Stream<bool> get hasUnreadChanges => _hasUnreadChanges.stream;
  final _hasUnreadChanges = StreamController<bool>.broadcast();

  Future<void> _refreshWhileUnread() async {
    if (!_hasUnread) return;
    try {
      await myPosts();
    } catch (_) {
      // Keep the last known dot; the next change or list load retries.
    }
  }

  Future<List<PostSummary>> myPosts() async {
    final posts = await _repository.myPosts();
    final hasUnread = postsHaveUnread(posts);
    if (hasUnread != _hasUnread) {
      _hasUnread = hasUnread;
      _hasUnreadChanges.add(hasUnread);
    }
    return posts;
  }
}

/// A conversation list has unread messages when any Post in it does.
bool postsHaveUnread(Iterable<PostSummary> posts) =>
    posts.any((post) => post.unreadCount > 0);
