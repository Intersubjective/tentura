import 'dart:async';

import '../../domain/entity/post_summary.dart';
import '../../domain/use_case/posts_case.dart';
import 'posts_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'posts_state.dart';

/// The «Разговоры» tab: the server filters and counts, the order and the
/// «Сейчас» / «Затихли» split are decided here, against an injectable clock.
class PostsCubit extends Cubit<PostsState> {
  PostsCubit({
    required PostsCase postsCase,
    DateTime Function()? clock,
  }) : _postsCase = postsCase,
       _clock = clock ?? DateTime.now,
       super(const PostsState(status: StateIsLoading())) {
    _changes = _postsCase.changes.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    unawaited(fetch());
  }

  /// A Post silent for this long (or longer) fades to «Затихли».
  static const quietAfter = Duration(hours: 72);

  final PostsCase _postsCase;
  final DateTime Function() _clock;
  late final StreamSubscription<void> _changes;
  var _generation = 0;

  @override
  Future<void> close() async {
    await _changes.cancel();
    return super.close();
  }

  Future<void> fetch() async {
    final generation = ++_generation;
    try {
      final posts = await _postsCase.myPosts();
      if (isClosed || generation != _generation) return;
      emit(_arrange(posts, _clock()));
    } on Object catch (e) {
      _postsCase.logger.warning('myPosts failed: $e');
      // Keep the list that was already shown.
      if (isClosed || generation != _generation) return;
      emit(state.copyWith(loaded: true, status: const StateIsSuccess()));
    }
  }

  static PostsState _arrange(List<PostSummary> posts, DateTime now) {
    final pinned = <PostSummary>[];
    final active = <PostSummary>[];
    final quiet = <PostSummary>[];
    for (final post in posts) {
      if (post.isPinned) {
        pinned.add(post);
      } else if (now.difference(post.lastActivityAt) < quietAfter) {
        active.add(post);
      } else {
        quiet.add(post);
      }
    }
    pinned.sort((a, b) => b.pinnedAt!.compareTo(a.pinnedAt!));
    int newestFirst(PostSummary a, PostSummary b) =>
        b.lastActivityAt.compareTo(a.lastActivityAt);
    active.sort(newestFirst);
    quiet.sort(newestFirst);
    return PostsState(
      loaded: true,
      pinned: pinned,
      active: active,
      quiet: quiet,
      now: now,
    );
  }
}
