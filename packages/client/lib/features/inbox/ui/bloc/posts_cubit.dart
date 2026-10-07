import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';

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
    RoomReadWatermarkStore? watermarks,
  }) : _postsCase = postsCase,
       _clock = clock ?? DateTime.now,
       super(const PostsState(status: StateIsLoading())) {
    _changes = _postsCase.changes.listen(
      (_) => unawaited(fetch()),
      cancelOnError: false,
    );
    _watchReads(
      watermarks ??
          (GetIt.I.isRegistered<RoomReadWatermarkStore>()
              ? GetIt.I<RoomReadWatermarkStore>()
              : null),
    );
    unawaited(fetch());
  }

  /// A Post silent for this long (or longer) fades to «Затихли».
  static const quietAfter = Duration(hours: 72);

  final PostsCase _postsCase;
  final DateTime Function() _clock;
  late final StreamSubscription<void> _changes;
  StreamSubscription<void>? _reads;
  var _generation = 0;

  @override
  Future<void> close() async {
    await _changes.cancel();
    await _reads?.cancel();
    return super.close();
  }

  /// Reading a Post's room (list reached the bottom, no message sent) never
  /// reaches the server as a beacon change the list could see, so the list
  /// refetches itself once a listed Post's read watermark is confirmed.
  void _watchReads(RoomReadWatermarkStore? watermarks) {
    if (watermarks == null) return;
    _reads = watermarks.threadChanges
        .where(
          (key) =>
              !watermarks.hasPendingSync(
                key.beaconId,
                threadId: key.threadId,
              ) &&
              state.pinned
                  .followedBy(state.active)
                  .followedBy(state.quiet)
                  .any((post) => post.id == key.beaconId),
        )
        .listen((_) => unawaited(fetch()), cancelOnError: false);
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
