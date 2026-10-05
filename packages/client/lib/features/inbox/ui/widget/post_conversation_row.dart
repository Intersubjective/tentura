import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

import '../../domain/entity/post_summary.dart';

/// One Post in «Разговоры» (M2): who, the root excerpt, the last message.
class PostConversationRow extends StatelessWidget {
  const PostConversationRow({
    required this.post,
    required this.now,
    required this.onOpen,
    this.selected = false,
    super.key,
  });

  final PostSummary post;

  /// The clock the list was arranged against; mute expiry and the age are
  /// read off it.
  final DateTime now;

  final VoidCallback onOpen;

  /// Open in the list-detail pane beside the list (Material 3 list-detail).
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final addressing = post.isAuthor
        ? l10n.postConversationYours
        : l10n.postConversationAddressed(post.authorName);
    final lastMessage = post.lastMessageExcerpt?.trim() ?? '';
    final muted = post.isMutedAt(now);

    return Semantics(
      label: [addressing, post.rootExcerpt, lastMessage].join(', '),
      selected: selected,
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.secondaryContainer
            : Colors.transparent,
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: tt.listRowPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ConversationImage(url: post.rootImageUrl),
                SizedBox(width: tt.avatarTextGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              addressing,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TenturaText.titleSmall(
                                tt.text,
                              ).copyWith(fontWeight: FontWeight.w500),
                            ),
                          ),
                          if (muted) ...[
                            SizedBox(width: tt.tightGap),
                            Icon(
                              Icons.notifications_off_outlined,
                              size: tt.iconSize,
                              color: tt.textFaint,
                              semanticLabel: l10n.postConversationMuted,
                            ),
                          ],
                        ],
                      ),
                      if (post.rootExcerpt.isNotEmpty) ...[
                        SizedBox(height: tt.tightGap),
                        Text(
                          post.rootExcerpt,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TenturaText.bodyMedium(tt.text),
                        ),
                      ],
                      if (lastMessage.isNotEmpty)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lastMessage,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TenturaText.bodySmall(tt.textMuted),
                              ),
                            ),
                            SizedBox(width: tt.iconTextGap),
                            Text(
                              compactRelativeTimeAgo(
                                when: post.lastActivityAt,
                                now: now,
                                l10n: l10n,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TenturaText.withTabular(
                                TenturaText.bodySmall(tt.textMuted),
                              ),
                              semanticsLabel: '',
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                if (post.unreadCount > 0) ...[
                  SizedBox(width: tt.iconTextGap),
                  // Neutral, not accent: a conversation list is not a feed.
                  TenturaCountBadge(
                    count: post.unreadCount,
                    backgroundColor: tt.textMuted,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Root-message artwork identifies the conversation independently of its author.
class _ConversationImage extends StatelessWidget {
  const _ConversationImage({required this.url});

  final String? url;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final placeholder = ColoredBox(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(
          Icons.forum_outlined,
          size: tt.iconSize,
          color: tt.textMuted,
        ),
      ),
    );
    final imageUrl = url?.trim() ?? '';
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(tt.cardRadius),
        child: SizedBox.square(
          dimension: tt.avatarSize,
          child: imageUrl.isEmpty
              ? placeholder
              : Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => placeholder,
                  loadingBuilder: (_, child, progress) =>
                      progress == null ? child : placeholder,
                ),
        ),
      ),
    );
  }
}
