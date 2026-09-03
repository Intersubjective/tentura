import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/test_ids.dart';
import 'package:tentura/ui/utils/relative_time.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

class UpdatesFeedGlyph {
  const UpdatesFeedGlyph({required this.icon, required this.color});

  final IconData icon;
  final Color color;
}

UpdatesFeedGlyph updatesFeedGlyphFor(
  AttentionReceipt receipt,
  TenturaTokens tt,
) {
  final key = receipt.presentationKey ?? '';
  if (isTrustChangePresentationKey(key)) {
    return switch (trustChangeDirectionFromPresentationKey(key)) {
      TrustChangeDirection.up => UpdatesFeedGlyph(
        icon: TenturaIcons.arrowUp,
        color: tt.good,
      ),
      TrustChangeDirection.down => UpdatesFeedGlyph(
        icon: TenturaIcons.arrowDown,
        color: tt.danger,
      ),
      TrustChangeDirection.neutral => UpdatesFeedGlyph(
        icon: TenturaIcons.updates,
        color: tt.textMuted,
      ),
    };
  }
  if (isInviteAcceptedPresentationKey(key) ||
      key == 'mutual_connection_formed') {
    return UpdatesFeedGlyph(icon: TenturaIcons.profile, color: tt.good);
  }
  return switch (key) {
    'needs_me' ||
    'blocker_opened' ||
    'blocker_resolved' ||
    'promise_made' ||
    'promise_withdrawn' ||
    'commitment_accepted' ||
    'commitment_resolved' ||
    'commitment_cancelled' ||
    'commitment_redirected' ||
    'help_offer_submitted' ||
    'offer_accepted' ||
    'offer_declined' ||
    'relay_received' => UpdatesFeedGlyph(
      icon: TenturaIcons.send,
      color: tt.warn,
    ),
    'room_message_posted' || 'roomMention' => UpdatesFeedGlyph(
      icon: TenturaIcons.comments,
      color: tt.info,
    ),
    _ => UpdatesFeedGlyph(icon: TenturaIcons.updates, color: tt.textMuted),
  };
}

/// Dense Updates feed row.
class UpdatesFeedTile extends StatelessWidget {
  const UpdatesFeedTile({
    required this.receipt,
    required this.onTap,
    required this.onMarkSeen,
    required this.onMarkUnseen,
    this.onSettle,
    this.headlineOverride,
    this.bodyOverride,
    this.action,
    super.key,
  });

  final AttentionReceipt receipt;
  final VoidCallback onTap;
  final VoidCallback onMarkSeen;
  final VoidCallback onMarkUnseen;
  final VoidCallback? onSettle;
  final String? headlineOverride;
  final String? bodyOverride;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final isUnread = !receipt.isSeen;
    final copy = resolveUpdatesFeedRowCopy(
      title: receipt.title,
      body: receipt.body,
      presentationKey: receipt.presentationKey,
      presentationPayloadJson: receipt.presentationPayloadJson,
      l10n: l10n,
      headlineOverride: headlineOverride,
      bodyOverride: bodyOverride,
    );
    final glyph = updatesFeedGlyphFor(receipt, tt);
    final localCreatedAt = receipt.createdAt.toLocal();
    final ageLabel = compactRelativeTimeAgo(
      when: receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';
    final rowAction =
        action ??
        (receipt.isLiveObligation && onSettle != null
            ? TenturaTextAction(
                label: l10n.updatesMarkDone,
                flushStart: true,
                onPressed: onSettle,
              )
            : null);

    return Semantics(
      identifier: TestIds.updatesReceipt(receipt.id),
      label: copy.headline,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return scheme.onSurface.withValues(alpha: 0.06);
            }
            if (states.contains(WidgetState.hovered)) {
              return scheme.onSurface.withValues(alpha: 0.03);
            }
            return null;
          }),
          child: Padding(
            padding: tt.listRowPadding,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _LeadingGlyph(glyph: glyph, unread: isUnread),
                SizedBox(width: tt.avatarTextGap),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              copy.headline,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TenturaText.titleSmall(tt.text).copyWith(
                                fontWeight: isUnread
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                            ),
                          ),
                          SizedBox(width: tt.iconTextGap),
                          Tooltip(
                            message: absoluteTime,
                            child: Text(
                              ageLabel,
                              style: TenturaText.withTabular(
                                TenturaText.bodySmall(tt.textFaint),
                              ),
                            ),
                          ),
                        ],
                      ),
                      if (copy.body.isNotEmpty)
                        Text(
                          copy.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TenturaText.bodySmall(tt.textMuted),
                        ),
                      if (rowAction != null) rowAction,
                    ],
                  ),
                ),
                _SeenTrailing(
                  unread: isUnread,
                  onMarkSeen: onMarkSeen,
                  onMarkUnseen: onMarkUnseen,
                  markSeenTooltip: l10n.updatesMarkSeen,
                  markUnseenTooltip: l10n.updatesMarkUnseen,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LeadingGlyph extends StatelessWidget {
  const _LeadingGlyph({required this.glyph, required this.unread});

  final UpdatesFeedGlyph glyph;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return SizedBox.square(
      dimension: tt.avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: unread ? tt.surface : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Icon(glyph.icon, size: tt.iconSize, color: glyph.color),
            ),
          ),
          if (unread)
            Positioned(
              right: 0,
              top: 0,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: tt.info,
                  shape: BoxShape.circle,
                  border: Border.all(color: tt.bg, width: tt.tightGap),
                ),
                child: SizedBox.square(dimension: tt.unreadDotSize),
              ),
            ),
        ],
      ),
    );
  }
}

class _SeenTrailing extends StatelessWidget {
  const _SeenTrailing({
    required this.unread,
    required this.onMarkSeen,
    required this.onMarkUnseen,
    required this.markSeenTooltip,
    required this.markUnseenTooltip,
  });

  final bool unread;
  final VoidCallback onMarkSeen;
  final VoidCallback onMarkUnseen;
  final String markSeenTooltip;
  final String markUnseenTooltip;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    if (unread) {
      return IconButton(
        tooltip: markSeenTooltip,
        onPressed: onMarkSeen,
        icon: Icon(Icons.radio_button_unchecked, color: tt.textFaint),
      );
    }
    return IconButton(
      tooltip: markUnseenTooltip,
      onPressed: onMarkUnseen,
      icon: Icon(Icons.check_circle, color: tt.good),
    );
  }
}
