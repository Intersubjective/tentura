import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/post_view/ui/post_remaining_label.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/widget/relative_timestamp_ticker.dart';

import '../../domain/entity/post_summary.dart';
import 'post_conversation_participants_copy.dart';

/// One Post in «Разговоры» (M2): who, the root excerpt, the last message.
class PostConversationRow extends StatelessWidget {
  const PostConversationRow({
    required this.post,
    required this.now,
    required this.onOpen,
    this.onOpenParticipants,
    this.selected = false,
    super.key,
  });

  final PostSummary post;

  /// The clock the list was arranged against; mute expiry is read off it.
  /// The age follows the shared [RelativeTimestampTicker] clock, so it keeps
  /// counting while the list stays open (#532).
  final DateTime now;

  final VoidCallback onOpen;

  /// Opens «О посте» at participants (#899); defaults to [onOpen] when null.
  final VoidCallback? onOpenParticipants;

  /// Open in the list-detail pane beside the list (Material 3 list-detail).
  final bool selected;

  /// Time left for an open Post (with ⏳, #248), «в архиве» once past deadline,
  /// «закрыт» when closed; null when there is no deadline and not archived.
  String? _lifetimeMarker(L10n l10n) {
    if (post.isClosed) return l10n.postClosedMarker;
    if (post.isArchivedAt(now)) return l10n.postArchivedMarker;
    final expiresAt = post.expiresAt;
    if (expiresAt == null) return null;
    return postRemainingVisibleLabel(l10n, expiresAt.difference(now));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final forwardedByName = post.forwardedByName;
    final addressing = post.isAuthor
        ? l10n.postConversationYours
        : forwardedByName != null
        ? l10n.postConversationForwarded(post.authorName, forwardedByName)
        : l10n.postConversationAddressed(post.authorName);
    final lastMessage = post.lastMessageExcerpt?.trim() ?? '';
    // #667: while the root is the only message, the last message is the root;
    // the row names it once and keeps the age.
    final lastMessageText = post.lastMessageIsRoot ? '' : lastMessage;
    final muted = post.isMutedAt(now);
    final lifetime = _lifetimeMarker(l10n);
    final participantsLine = postConversationShowsParticipantsLine(post)
        ? postConversationParticipantsLine(l10n, post)
        : null;
    final previewProfiles = [
      for (final peer in post.previewParticipants) peer.toProfile(),
    ];

    return Semantics(
      label: [
        addressing,
        ?lifetime,
        post.rootExcerpt,
        ?participantsLine,
        if (lastMessageText.isNotEmpty) lastMessageText,
      ].join(', '),
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
                          if (lifetime != null) ...[
                            SizedBox(width: tt.iconTextGap),
                            TenturaStatusText(
                              lifetime,
                              key: const Key('PostConversation.Lifetime'),
                            ),
                          ],
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
                      if (participantsLine != null) ...[
                        SizedBox(height: tt.tightGap),
                        _ParticipantsLine(
                          line: participantsLine,
                          profiles: previewProfiles,
                          onTap: onOpenParticipants ?? onOpen,
                        ),
                      ],
                      if (lastMessage.isNotEmpty)
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                lastMessageText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TenturaText.bodySmall(tt.textMuted),
                              ),
                            ),
                            SizedBox(width: tt.iconTextGap),
                            // #476: the card's short age («7m»), as the
                            // Request cards and Post rows beside it read.
                            RelativeTimestampTicker(
                              builder: (_) => Text(
                                cardRelativeAge(
                                  when: post.lastActivityAt,
                                  now: RelativeTimestampTicker.now(),
                                  l10n: l10n,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TenturaText.withTabular(
                                  TenturaText.bodySmall(tt.textMuted),
                                ),
                                semanticsLabel: '',
                              ),
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

/// Key for the tappable participants line under a Post row (#899).
const postConversationParticipantsKey = Key('PostConversation.Participants');

class _ParticipantsLine extends StatelessWidget {
  const _ParticipantsLine({
    required this.line,
    required this.profiles,
    required this.onTap,
  });

  static const lineKey = postConversationParticipantsKey;

  final String line;
  final List<Profile> profiles;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final l10n = L10n.of(context)!;
    return Semantics(
      button: true,
      label: '${l10n.postConversationParticipantsSemantics}: $line',
      child: InkWell(
        key: lineKey,
        onTap: onTap,
        child: Row(
          children: [
            if (profiles.isNotEmpty) ...[
              TenturaAvatarStack(
                profiles: profiles,
                max: 4,
                sizeBucket: TenturaAvatarSize.tiny,
              ),
              SizedBox(width: tt.iconTextGap),
            ],
            Expanded(
              child: Text(
                line,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TenturaText.bodySmall(tt.textMuted),
              ),
            ),
          ],
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
