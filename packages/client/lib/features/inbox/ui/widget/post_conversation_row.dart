import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

import '../../domain/entity/post_summary.dart';

/// One Post in «Разговоры» (M2): who, the root excerpt, the last message.
class PostConversationRow extends StatelessWidget {
  const PostConversationRow({
    required this.post,
    required this.now,
    required this.onOpen,
    super.key,
  });

  final PostSummary post;

  /// The clock the list was arranged against; mute expiry and the age are
  /// read off it.
  final DateTime now;

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final author = Profile(
      id: post.authorId,
      displayName: post.authorName,
      image: post.authorAvatar.isEmpty || post.authorAvatar == 'null'
          ? null
          : ImageEntity(id: post.authorAvatar, authorId: post.authorId),
    );
    final addressing = post.isAuthor
        ? l10n.postConversationYours
        : l10n.postConversationAddressed(post.authorName);
    final lastMessage = post.lastMessageExcerpt?.trim() ?? '';
    final muted = post.isMutedAt(now);

    return Semantics(
      label: [addressing, post.rootExcerpt, lastMessage].join(', '),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: tt.listRowPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TenturaAvatar.medium(profile: author),
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
