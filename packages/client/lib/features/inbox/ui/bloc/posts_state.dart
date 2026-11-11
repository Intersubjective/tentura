import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/post_summary.dart';
import '../../domain/entity/posts_filter.dart';

import '../../domain/use_case/posts_case.dart';

export '../../domain/entity/posts_filter.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'posts_state.freezed.dart';

@freezed
abstract class PostsState extends StateBase with _$PostsState {
  const factory PostsState({
    /// Set by the first fetch; before it the tab shows a spinner, not the
    /// empty state.
    @Default(false) bool loaded,

    /// Pinned by `pinnedAt`, the most recently pinned first.
    @Default([]) List<PostSummary> pinned,

    /// Unpinned and still within their lifetime («Сейчас»).
    @Default([]) List<PostSummary> active,

    /// Unpinned and closed or past their deadline («Архив»).
    @Default([]) List<PostSummary> archive,

    /// Unpublished Posts owned by the viewer.
    @Default([]) List<PostSummary> drafts,
    @Default(PostsFilter.active) PostsFilter filter,

    /// The clock the sections were split against.
    DateTime? now,
    @Default(StateIsSuccess()) StateStatus status,

    /// Why the fetch failed; only set until one fetch has succeeded.
    Object? loadError,
  }) = _PostsState;

  const PostsState._();

  List<PostSummary> get visiblePosts => switch (filter) {
    PostsFilter.active => [...pinned, ...active],
    PostsFilter.authored => [
      ...pinned,
      ...active,
      ...archive,
    ].where((post) => post.isAuthor).toList(),
    PostsFilter.drafts => drafts,
    PostsFilter.archived => archive,
  };

  bool get isEmpty => visiblePosts.isEmpty;

  bool get hasUnread => postsHaveUnread([...pinned, ...active, ...archive]);
}
