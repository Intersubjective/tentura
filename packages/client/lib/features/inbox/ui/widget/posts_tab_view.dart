import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_kind.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/navigation/app_navigator.dart';

import '../../domain/entity/post_summary.dart';
import '../bloc/posts_cubit.dart';
import 'post_conversation_row.dart';

String postsFilterLabel(L10n l10n, PostsFilter filter) => switch (filter) {
  PostsFilter.active => l10n.postsFilterActive,
  PostsFilter.authored => l10n.postsFilterAuthored,
  PostsFilter.drafts => l10n.postsFilterDrafts,
  PostsFilter.archived => l10n.postsTabArchive,
};

/// The selected Posts view, with a single drafts entry point in Active.
class PostsTabView extends StatelessWidget {
  const PostsTabView({
    this.canCreatePost = kPostsEnabled,
    this.onCreatePost,
    this.onOpenPost,
    this.onOpenPostParticipants,
    this.scrollController,
    super.key,
  });

  /// Whether the empty state offers «Новый пост» (a new Post).
  final bool canCreatePost;

  final VoidCallback? onCreatePost;

  /// Opens a Post; null pushes its route. Inbox's list-detail passes one that
  /// shows the Post beside this list.
  final ValueChanged<String>? onOpenPost;

  /// Opens «О посте» at participants for the given post id (#899).
  final ValueChanged<String>? onOpenPostParticipants;

  final ScrollController? scrollController;

  Future<void> _deleteDraft(BuildContext context, String id) async {
    final l10n = L10n.of(context)!;
    final confirmed = await TenturaConfirmDialog.show(
      context: context,
      title: l10n.postCreateDiscardTitle,
      content: l10n.postCreateDiscardBody,
      confirmLabel: l10n.postCreateDiscardConfirm,
      cancelLabel: l10n.buttonCancel,
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await GetIt.I<BeaconRepository>().delete(id);
      if (context.mounted) await context.read<PostsCubit>().fetch();
    } catch (error) {
      if (context.mounted) {
        context.read<ScreenCubit>().effects.emit(ShowError(error));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    return BlocBuilder<PostsCubit, PostsState>(
      builder: (context, state) {
        if (!state.loaded) {
          return const Center(child: TenturaCircularProgress());
        }
        final showDraftsShortcut =
            state.filter == PostsFilter.active && state.drafts.isNotEmpty;
        void showDrafts() =>
            context.read<PostsCubit>().setFilter(PostsFilter.drafts);
        if (state.isEmpty) {
          return TenturaEmptyState(
            icon: Icons.forum_outlined,
            title: l10n.postsTabEmpty,
            actionLabel: showDraftsShortcut
                ? l10n.myWorkEmptyDraftsShortcut(state.drafts.length)
                : canCreatePost
                ? l10n.postsTabNewPost
                : null,
            onAction: showDraftsShortcut
                ? showDrafts
                : canCreatePost
                ? onCreatePost
                : null,
          );
        }
        final now = state.now ?? DateTime.now();
        final selectedId = TenturaListDetailSelection.of(context);
        Widget row(PostSummary post) => PostConversationRow(
          key: ValueKey(post.id),
          post: post,
          now: now,
          selected: post.id == selectedId,
          onOpen: () => post.isDraft
              ? GetIt.I<AppNavigator>().createPost(draftId: post.id)
              : onOpenPost == null
              ? GetIt.I<AppNavigator>().openBeacon(
                  post.id,
                  kind: BeaconKind.post,
                )
              : onOpenPost!(post.id),
          onDeleteDraft: post.isDraft
              ? () => _deleteDraft(context, post.id)
              : null,
          onOpenParticipants: onOpenPostParticipants == null
              ? null
              : () => onOpenPostParticipants!(post.id),
        );
        return ListView(
          controller: scrollController,
          children: [
            if (showDraftsShortcut)
              ListTile(
                title: Text(l10n.postsDraftsCount(state.drafts.length)),
                onTap: showDrafts,
              ),
            for (final post in state.visiblePosts) row(post),
          ],
        );
      },
    );
  }
}
