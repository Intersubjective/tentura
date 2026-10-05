import 'dart:async';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/features/home/ui/bloc/home_tab_reselect_cubit.dart';
import 'package:tentura/features/home/ui/widget/home_account_avatar_button.dart';
import 'package:tentura/features/post_view/ui/screen/post_view_scope.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';

import '../bloc/posts_cubit.dart';
import '../widget/posts_tab_view.dart';

/// Conversations: the viewer's Posts, a Home destination of its own.
///
/// Material 3 list-detail: with room, the list sits in a 440 dp pane and the
/// chosen Post's chat opens beside it (Home's rail, the list, the chat);
/// narrower, a Post is pushed full screen. [PostsCubit] comes from Home's
/// shell, which keeps the Conversations nav dot current.
@RoutePage()
class ConversationsScreen extends StatefulWidget {
  const ConversationsScreen({
    this.canCreatePost,
    @visibleForTesting this.postPaneBuilder,
    super.key,
  });

  /// Whether the top bar offers starting a Post; defaults to [kPostsEnabled].
  final bool? canCreatePost;

  /// Builds the chat pane for a Post; defaults to [PostViewScope].
  final Widget Function(String postId, VoidCallback onClose)? postPaneBuilder;

  @override
  State<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends State<ConversationsScreen> {
  final _scrollController = ScrollController();

  /// The Post open in the chat pane beside the list (wide windows only).
  String? _selectedPostId;

  /// Whether the last layout had room for the list and the chat side by side.
  var _canSplit = false;

  /// Keeps the list's state (scroll) when the chat pane opens or closes.
  final _listKey = GlobalKey(debugLabel: 'conversations-list');

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _openPost(String id) {
    if (_canSplit) {
      setState(() => _selectedPostId = id);
    } else {
      unawaited(context.router.push(BeaconViewRoute(id: id)));
    }
  }

  void _closePost() {
    if (_selectedPostId == null || !mounted) return;
    setState(() => _selectedPostId = null);
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    unawaited(
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      BlocListener<HomeTabReselectCubit, HomeTabReselectState>(
        listenWhen: (prev, curr) =>
            prev.conversationsReselectCount != curr.conversationsReselectCount,
        listener: (_, _) => _scrollToTop(),
        child: _SelectedPostPruner(
          selectedPostId: _selectedPostId,
          onGone: _closePost,
          child: LayoutBuilder(
            builder: (context, constraints) {
              _canSplit =
                  constraints.maxWidth >=
                  TenturaSpacing.listPaneWidth +
                      TenturaSpacing.supportingPrimaryMinWidth;
              final selectedPostId = _canSplit ? _selectedPostId : null;
              final list = KeyedSubtree(
                key: _listKey,
                child: TenturaListDetailSelection(
                  selectedId: selectedPostId ?? '',
                  child: _buildList(context, split: _canSplit),
                ),
              );
              if (!_canSplit) return list;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    key: TenturaListDetailLayout.listPaneKey,
                    width: TenturaSpacing.listPaneWidth,
                    child: list,
                  ),
                  const TenturaVerticalHairline(),
                  Expanded(
                    child: selectedPostId == null
                        ? const _NoConversationPane()
                        : _buildPostPane(context, selectedPostId),
                  ),
                ],
              );
            },
          ),
        ),
      );

  /// The chat starts at the list's edge rather than floating mid-pane.
  Widget _buildPostPane(BuildContext context, String postId) =>
      TenturaChatColumnScope(
        alignment: AlignmentDirectional.topStart,
        child:
            widget.postPaneBuilder?.call(postId, _closePost) ??
            PostViewScope(
              id: postId,
              myProfile: context.read<ProfileCubit>().state.profile,
              onClose: _closePost,
            ),
      );

  Widget _buildList(BuildContext context, {required bool split}) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context)!;
    final canCreatePost = widget.canCreatePost ?? kPostsEnabled;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: TenturaTopBar.of(
        context,
        tone: TenturaTopBarTone.primary,
        alignment: !split && context.windowClass == WindowClass.expanded
            ? TenturaTopBarAlignment.fullWidth
            : TenturaTopBarAlignment.content,
        title: Text(
          l10n.activityTabConversations,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TenturaText.titleLarge(scheme.onSurface),
        ),
        actions: [
          if (canCreatePost)
            IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: l10n.postsTabNewPost,
              onPressed: () => context.read<ScreenCubit>().showPostCreate(),
            ),
        ],
        account: homeTopBarAccount(context),
      ),
      body: SafeArea(
        minimum: EdgeInsets.symmetric(horizontal: context.tt.screenHPadding),
        child: TenturaContentColumn(
          child: PostsTabView(
            canCreatePost: canCreatePost,
            onCreatePost: () => context.read<ScreenCubit>().showPostCreate(),
            onOpenPost: _openPost,
            scrollController: _scrollController,
          ),
        ),
      ),
    );
  }
}

/// Clears the chat pane once its Post leaves the list (deleted, left, or
/// gone after a refresh).
class _SelectedPostPruner extends StatelessWidget {
  const _SelectedPostPruner({
    required this.selectedPostId,
    required this.onGone,
    required this.child,
  });

  final String? selectedPostId;
  final VoidCallback onGone;
  final Widget child;

  @override
  Widget build(BuildContext context) => BlocListener<PostsCubit, PostsState>(
    listenWhen: (_, curr) => curr.loaded,
    listener: (context, state) {
      final id = selectedPostId;
      if (id == null) return;
      final listed = [
        ...state.pinned,
        ...state.active,
        ...state.quiet,
      ].any((post) => post.id == id);
      if (!listed) onGone();
    },
    child: child,
  );
}

/// The chat pane before a conversation is chosen.
class _NoConversationPane extends StatelessWidget {
  const _NoConversationPane();

  @override
  Widget build(BuildContext context) => Scaffold(
    body: TenturaEmptyState(
      icon: Icons.forum_outlined,
      title: L10n.of(context)!.postsTabSelectConversation,
    ),
  );
}
