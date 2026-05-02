import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/capability/ui/widget/forward_capability_chips.dart';
import 'package:tentura/features/forward/domain/entity/forward_edge.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';

const _kAvatarSize = 18.0;
const _kBarColumnWidth = 18.0;

/// One forward entry in the same visual style as the expanded inbox forwards fold
/// (`_SenderNoteBlock` in `inbox_card_forwards_fold.dart`).
class UnifiedForwardRow extends StatelessWidget {
  const UnifiedForwardRow._({
    required this.viewerUserId,
    required this.reasonSlugs,
    this.inboundSender,
    this.inboundNote,
    this.outboundEdge,
    this.involvementCommittedIds,
    this.involvementWatchingIds,
    this.involvementOnwardForwarderIds,
    super.key,
  }) : assert(
          (inboundSender != null && inboundNote != null && outboundEdge == null) ||
              (outboundEdge != null &&
                  inboundSender == null &&
                  inboundNote == null &&
                  involvementCommittedIds != null &&
                  involvementWatchingIds != null &&
                  involvementOnwardForwarderIds != null),
          'Use .inbound or .outgoing factory with matching optional fields',
        );

  factory UnifiedForwardRow.inbound({
    required Profile sender,
    required String note,
    required String viewerUserId,
    List<String> reasonSlugs = const [],
    Key? key,
  }) =>
      UnifiedForwardRow._(
        viewerUserId: viewerUserId,
        reasonSlugs: reasonSlugs,
        inboundSender: sender,
        inboundNote: note,
        key: key,
      );

  factory UnifiedForwardRow.outgoing({
    required ForwardEdge edge,
    required String viewerUserId,
    required Set<String> committed,
    required Set<String> watching,
    required Set<String> onward,
    List<String> reasonSlugs = const [],
    Key? key,
  }) =>
      UnifiedForwardRow._(
        viewerUserId: viewerUserId,
        reasonSlugs: reasonSlugs,
        outboundEdge: edge,
        involvementCommittedIds: committed,
        involvementWatchingIds: watching,
        involvementOnwardForwarderIds: onward,
        key: key,
      );

  final String viewerUserId;
  final List<String> reasonSlugs;

  final Profile? inboundSender;
  final String? inboundNote;

  final ForwardEdge? outboundEdge;
  final Set<String>? involvementCommittedIds;
  final Set<String>? involvementWatchingIds;
  final Set<String>? involvementOnwardForwarderIds;

  bool get _isInbound => outboundEdge == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context)!;

    if (_isInbound) {
      return _buildInbound(context, theme, scheme, l10n);
    }
    return _buildOutgoing(context, theme, scheme, l10n);
  }

  Widget _buildInbound(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    L10n l10n,
  ) {
    final sender = inboundSender!;
    final displayName =
        SelfUserHighlight.displayName(l10n, sender, viewerUserId).trim();
    final note = inboundNote!.trim();

    final header = Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Flexible(
          child: Text(
            displayName,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
        const SizedBox(width: 6),
        AvatarRated(
          profile: sender,
          size: _kAvatarSize,
          withRating: false,
        ),
      ],
    );

    return _NoteColumnWithBar(
      theme: theme,
      scheme: scheme,
      header: header,
      note: note,
      reasonSlugs: reasonSlugs,
      reactionRows: const [],
    );
  }

  Widget _buildOutgoing(
    BuildContext context,
    ThemeData theme,
    ColorScheme scheme,
    L10n l10n,
  ) {
    final edge = outboundEdge!;
    final sender = edge.sender;
    final recipient = edge.recipient;

    final baseName = theme.textTheme.labelSmall?.copyWith(
      fontWeight: FontWeight.w700,
      color: scheme.onSurface,
    );

    final header = Row(
      children: [
        _AvatarRinged(
          profile: sender,
          viewerUserId: viewerUserId,
          size: _kAvatarSize,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            SelfUserHighlight.displayName(l10n, sender, viewerUserId),
            style: SelfUserHighlight.nameStyle(
              theme,
              baseName,
              SelfUserHighlight.profileIsSelf(sender, viewerUserId),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Icon(
            Icons.arrow_forward,
            size: 14,
            color: scheme.onSurfaceVariant,
          ),
        ),
        _AvatarRinged(
          profile: recipient,
          viewerUserId: viewerUserId,
          size: _kAvatarSize,
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            SelfUserHighlight.displayName(l10n, recipient, viewerUserId),
            style: SelfUserHighlight.nameStyle(
              theme,
              baseName,
              SelfUserHighlight.profileIsSelf(recipient, viewerUserId),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.start,
          ),
        ),
      ],
    );

    final reactionRows = _outgoingReactionRows(
      scheme,
      l10n,
      edge,
      involvementCommittedIds!,
      involvementWatchingIds!,
      involvementOnwardForwarderIds!,
    );

    return _NoteColumnWithBar(
      theme: theme,
      scheme: scheme,
      header: header,
      note: edge.note.trim(),
      reasonSlugs: reasonSlugs,
      reactionRows: reactionRows,
      barTrailing: false,
    );
  }

  List<Widget> _outgoingReactionRows(
    ColorScheme scheme,
    L10n l10n,
    ForwardEdge edge,
    Set<String> committed,
    Set<String> watching,
    Set<String> onward,
  ) {
    final id = edge.recipient.id;
    if (edge.recipientRejected) {
      final text = edge.recipientRejectionMessage.isNotEmpty
          ? l10n.myForwardDeclinedWithReason(edge.recipientRejectionMessage)
          : l10n.myForwardDeclined;
      return [
        _ReactionLine(
          icon: Icons.block,
          text: text,
          iconColor: scheme.error,
          textColor: scheme.error,
          alignEnd: false,
        ),
      ];
    }
    if (committed.contains(id)) {
      return [
        _ReactionLine(
          icon: Icons.check_circle_outline,
          text: l10n.forwardReactionCommitted,
          iconColor: scheme.tertiary,
          alignEnd: false,
        ),
      ];
    }
    if (onward.contains(id)) {
      return [
        _ReactionLine(
          icon: Icons.forward_to_inbox,
          text: l10n.forwardReactionForwardedOnward,
          alignEnd: false,
        ),
      ];
    }
    if (watching.contains(id)) {
      return [
        _ReactionLine(
          icon: Icons.visibility_outlined,
          text: l10n.forwardReactionWatching,
          alignEnd: false,
        ),
      ];
    }
    return const [];
  }
}

class _AvatarRinged extends StatelessWidget {
  const _AvatarRinged({
    required this.profile,
    required this.viewerUserId,
    required this.size,
  });

  final Profile profile;
  final String viewerUserId;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final self = SelfUserHighlight.profileIsSelf(profile, viewerUserId);
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: self ? scheme.primary : scheme.surfaceContainerLowest,
          width: self ? 2 : 1,
        ),
      ),
      child: AvatarRated(
        profile: profile,
        withRating: false,
        size: size,
      ),
    );
  }
}

class _ReactionLine extends StatelessWidget {
  const _ReactionLine({
    required this.icon,
    required this.text,
    this.iconColor,
    this.textColor,
    this.alignEnd = true,
  });

  final IconData icon;
  final String text;
  final Color? iconColor;
  final Color? textColor;
  final bool alignEnd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final effectiveTextColor = textColor ?? scheme.onSurfaceVariant;
    final textAlign = alignEnd ? TextAlign.end : TextAlign.start;
    return Row(
      mainAxisAlignment:
          alignEnd ? MainAxisAlignment.end : MainAxisAlignment.start,
      children: [
        Icon(
          icon,
          size: 16,
          color: iconColor ?? scheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            textAlign: textAlign,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: effectiveTextColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteColumnWithBar extends StatelessWidget {
  const _NoteColumnWithBar({
    required this.theme,
    required this.scheme,
    required this.header,
    required this.note,
    required this.reactionRows,
    this.reasonSlugs = const [],
    this.barTrailing = true,
  });

  final ThemeData theme;
  final ColorScheme scheme;
  final Widget header;
  final String note;
  final List<String> reasonSlugs;
  final List<Widget> reactionRows;

  /// When `true` (inbound), bar is on the right and content is end-aligned.
  /// When `false` (outgoing / viewer's forwards), bar is on the left and content is start-aligned.
  final bool barTrailing;

  @override
  Widget build(BuildContext context) {
    final noteTrim = note.trim();
    final hasNote = noteTrim.isNotEmpty;
    final hasReactions = reactionRows.isNotEmpty;
    final hasChips = reasonSlugs.isNotEmpty;

    if (!hasNote && !hasReactions && !hasChips) {
      return Align(
        alignment: barTrailing ? Alignment.centerRight : Alignment.centerLeft,
        child: header,
      );
    }

    final textAlign = barTrailing ? TextAlign.end : TextAlign.start;
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      color: scheme.onSurfaceVariant,
      fontStyle: FontStyle.italic,
      height: 1.35,
    );

    final lowerChildren = <Widget>[];
    if (hasNote) {
      lowerChildren.add(
        Text(
          noteTrim,
          textAlign: textAlign,
          style: textStyle,
        ),
      );
    }
    if (hasChips) {
      if (hasNote) lowerChildren.add(const SizedBox(height: 4));
      lowerChildren.add(
        Align(
          alignment: barTrailing ? Alignment.centerRight : Alignment.centerLeft,
          child: ForwardCapabilityChips(slugs: reasonSlugs),
        ),
      );
    }
    if (hasReactions) {
      if (hasNote || hasChips) {
        lowerChildren.add(const SizedBox(height: 8));
      }
      for (var i = 0; i < reactionRows.length; i++) {
        if (i > 0) {
          lowerChildren.add(const SizedBox(height: 4));
        }
        lowerChildren.add(reactionRows[i]);
      }
    }

    final bar = SizedBox(
      width: _kBarColumnWidth,
      child: Center(
        child: Container(
          width: 2,
          height: double.infinity,
          color: scheme.primary.withValues(alpha: 0.45),
        ),
      ),
    );

    final afterHeaderGap = hasNote ? 2.0 : 4.0;

    if (barTrailing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          header,
          SizedBox(height: afterHeaderGap),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: lowerChildren,
                  ),
                ),
                bar,
              ],
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(width: _kBarColumnWidth),
            const SizedBox(width: 8),
            Expanded(child: header),
          ],
        ),
        SizedBox(height: afterHeaderGap),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              bar,
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: lowerChildren,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
