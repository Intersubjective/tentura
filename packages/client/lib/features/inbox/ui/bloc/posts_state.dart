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

    /// Unpinned, active within the last 72 h («Сейчас»).
    @Default([]) List<PostSummary> active,

    /// Unpinned, silent for 72 h or more («Затихли»).
    @Default([]) List<PostSummary> quiet,

    /// The clock the sections were split against.
    DateTime? now,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _PostsState;

  const PostsState._();

  bool get isEmpty => pinned.isEmpty && active.isEmpty && quiet.isEmpty;

  bool get hasUnread => postsHaveUnread([...pinned, ...active, ...quiet]);
}
