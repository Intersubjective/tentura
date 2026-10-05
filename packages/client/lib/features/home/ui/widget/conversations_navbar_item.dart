import 'package:flutter/material.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/features/inbox/domain/use_case/posts_case.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Conversations destination icon with a dot while a Post has unread
/// messages.
///
/// Reads [PostsCase] rather than a shell cubit, so the dot also shows on the
/// rail of routes pushed above Home ([HomeRailFrame]).
class ConversationsNavbarItem extends StatelessWidget {
  const ConversationsNavbarItem({super.key, this.selected = false});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(selected ? Icons.forum : Icons.forum_outlined);
    if (!GetIt.I.isRegistered<PostsCase>()) return icon;
    final postsCase = GetIt.I<PostsCase>();
    return StreamBuilder<bool>(
      stream: postsCase.hasUnreadChanges,
      initialData: postsCase.hasUnread,
      builder: (context, snapshot) {
        if (!(snapshot.data ?? false)) return icon;
        return Semantics(
          label: L10n.of(context)!.activityNavBadgeNewActivity,
          identifier: 'conversations-unread-dot',
          child: Badge(
            backgroundColor: Theme.of(context).colorScheme.primary,
            child: icon,
          ),
        );
      },
    );
  }
}
