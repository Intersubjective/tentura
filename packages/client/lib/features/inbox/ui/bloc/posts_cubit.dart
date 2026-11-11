import 'dart:async';

import 'package:get_it/get_it.dart';

import 'package:tentura/features/beacon_threads/domain/room_read_watermark_store.dart';
import 'package:tentura/ui/bloc/reload_when_online.dart';
import 'package:tentura/ui/utils/post_expiry_clock.dart';

import '../../domain/entity/post_summary.dart';
import '../../domain/use_case/posts_case.dart';
import 'posts_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'posts_state.dart';

/// The «Разговоры» tab: the server filters and counts, the order and the
/// «Сейчас» / «Архив» split are decided here, against an injectable clock.
/// A [PostExpiryClock] re-arranges the list when a Post's deadline passes, so
/// no network event is needed to move it.
class PostsCubit extends Cubit<PostsState> {
  PostsCubit({
    required PostsCase postsCase,
    DateTime Function()? clock,
    RoomReadWatermarkStore? watermarks,
  }) : _postsCase = postsCase,
       _clock = clock ?? DateTime.now,
       super(const PostsState(status: StateIsLoading())) {
    _expiry = PostExpiryClock(onTick: _rearrange, clock: _clock);
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
    _reloadWhenOnline = ReloadWhenOnline(
      lastLoadFailed: () => _lastFetchFailed,
      reload: () => unawaited(fetch()),
    );
    unawaited(fetch());
  }

  final PostsCase _postsCase;
  final DateTime Function() _clock;
  late final StreamSubscription<void> _changes;
  late final PostExpiryClock _expiry;
  var _posts = const <PostSummary>[];
  StreamSubscription<void>? _reads;
  var _generation = 0;
  var _lastFetchFailed = false;
  late final ReloadWhenOnline _reloadWhenOnline;

  @override
  Future<void> close() async {
    _expiry.dispose();
    await _reloadWhenOnline.close();
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
                  .followedBy(state.archive)
                  .any((post) => post.id == key.beaconId),
        )
        .listen((_) => unawaited(fetch()), cancelOnError: false);
  }

  Future<void> fetch() async {
    final generation = ++_generation;
    try {
      final posts = await _postsCase.myPosts();
      if (isClosed || generation != _generation) return;
      _lastFetchFailed = false;
      _posts = posts;
      _expiry.setDeadlines({
        for (final post in posts)
          if (!post.isDraft && !post.isClosed && post.expiresAt != null)
            post.expiresAt!,
      });
      emit(_arrange(posts, _clock()));
    } on Object catch (e) {
      _postsCase.logger.warning('myPosts failed: $e');
      // Keep the list that was already shown.
      if (isClosed || generation != _generation) return;
      _lastFetchFailed = true;
      emit(state.copyWith(loaded: true, status: const StateIsSuccess()));
    }
  }

  /// Time alone moved a deadline or the last-hour countdown: re-split the
  /// listed Posts against the new clock reading, with no refetch.
  void _rearrange() {
    if (isClosed || !state.loaded) return;
    emit(_arrange(_posts, _clock()));
  }

  void setFilter(PostsFilter filter) => emit(state.copyWith(filter: filter));

  PostsState _arrange(List<PostSummary> posts, DateTime now) {
    final pinned = <PostSummary>[];
    final active = <PostSummary>[];
    final archive = <PostSummary>[];
    final drafts = <PostSummary>[];
    for (final post in posts) {
      if (post.isDraft) {
        if (post.isAuthor) drafts.add(post);
      } else if (post.isPinned) {
        pinned.add(post);
      } else if (!post.isArchivedAt(now)) {
        active.add(post);
      } else {
        archive.add(post);
      }
    }
    pinned.sort((a, b) => b.pinnedAt!.compareTo(a.pinnedAt!));
    // By last activity, never by deadline (a conversation list is not a feed
    // ranked by urgency).
    int newestFirst(PostSummary a, PostSummary b) =>
        b.lastActivityAt.compareTo(a.lastActivityAt);
    active.sort(newestFirst);
    archive.sort(newestFirst);
    drafts.sort(newestFirst);
    return state.copyWith(
      status: const StateIsSuccess(),
      loaded: true,
      drafts: drafts,
      pinned: pinned,
      active: active,
      archive: archive,
      now: now,
    );
  }
}
