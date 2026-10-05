import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../../domain/entity/post_summary.dart';
import '../bloc/posts_cubit.dart';
import 'post_conversation_row.dart';

/// The Conversations list: pinned Posts, then «Сейчас», then «Затихли».
class PostsTabView extends StatelessWidget {
  const PostsTabView({
    this.canCreatePost = kPostsEnabled,
    this.onCreatePost,
    this.onOpenPost,
    this.scrollController,
    super.key,
  });

  /// Whether the empty state offers «Новый пост».
  final bool canCreatePost;

  final VoidCallback? onCreatePost;

  /// Opens a Post; null pushes its route. Inbox's list-detail passes one that
  /// shows the Post beside this list.
  final ValueChanged<String>? onOpenPost;

  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocBuilder<PostsCubit, PostsState>(
      builder: (context, state) {
        if (!state.loaded) {
          return const Center(child: CircularProgressIndicator());
        }
        if (state.isEmpty) {
          return TenturaEmptyState(
            icon: Icons.forum_outlined,
            title: l10n.postsTabEmpty,
            actionLabel: canCreatePost ? l10n.postsTabNewPost : null,
            onAction: canCreatePost ? onCreatePost : null,
          );
        }
        final now = state.now ?? DateTime.now();
        final selectedId = TenturaListDetailSelection.of(context);
        Widget row(PostSummary post) => PostConversationRow(
          key: ValueKey(post.id),
          post: post,
          now: now,
          selected: post.id == selectedId,
          onOpen: () => onOpenPost == null
              ? context.router.push(BeaconViewRoute(id: post.id))
              : onOpenPost!(post.id),
        );
        return ListView(
          controller: scrollController,
          children: [
            for (final post in state.pinned) row(post),
            if (state.active.isNotEmpty) ...[
              TenturaSectionHeader(label: l10n.postsTabNow),
              for (final post in state.active) row(post),
            ],
            if (state.quiet.isNotEmpty) ...[
              TenturaSectionHeader(label: l10n.postsTabQuiet),
              for (final post in state.quiet) row(post),
            ],
          ],
        );
      },
    );
  }
}
