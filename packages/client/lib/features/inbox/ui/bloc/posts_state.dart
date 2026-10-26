import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/post_summary.dart';
import '../../domain/use_case/posts_case.dart';

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

    /// The clock the sections were split against.
    DateTime? now,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _PostsState;

  const PostsState._();

  bool get isEmpty => pinned.isEmpty && active.isEmpty && archive.isEmpty;

  bool get hasUnread => postsHaveUnread([...pinned, ...active, ...archive]);
}
