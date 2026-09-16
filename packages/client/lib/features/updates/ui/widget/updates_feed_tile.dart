import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/attention/entity/attention_receipt.dart';
import 'package:tentura/domain/contacts/contact_name_overlay.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/features/updates/updates_receipt_display_copy.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
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
    'request_status_changed' => UpdatesFeedGlyph(
      icon: TenturaIcons.switcher,
      color: tt.info,
    ),
    'offer_accepted' => UpdatesFeedGlyph(
      icon: TenturaIcons.favorites,
      color: tt.good,
    ),
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
class UpdatesFeedTile extends StatefulWidget {
  const UpdatesFeedTile({
    required this.receipt,
    required this.onTap,
    required this.onMarkSeen,
    required this.onMarkUnseen,
    this.onSettle,
    this.headlineOverride,
    this.bodyOverride,
    this.action,
    this.actor,
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

  /// When non-null, leading shows a tappable [TenturaAvatar.medium] instead of
  /// the type glyph. Must sit outside the row [InkWell].
  final Profile? actor;

  @override
  State<UpdatesFeedTile> createState() => _UpdatesFeedTileState();
}

class _UpdatesFeedTileState extends State<UpdatesFeedTile> {
  bool _hovering = false;

  bool get _isUnread => !widget.receipt.isSeen;

  void _markSeen() => widget.onMarkSeen();

  void _markUnseen() => widget.onMarkUnseen();

  void _showMarkMenu() {
    final l10n = L10n.of(context)!;
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final position = RelativeRect.fromLTRB(
      origin.dx,
      origin.dy,
      overlay.size.width - origin.dx - box.size.width,
      overlay.size.height - origin.dy - box.size.height,
    );
    unawaited(
      showMenu<void>(
        context: context,
        position: position,
        items: [
          if (_isUnread)
            PopupMenuItem<void>(
              onTap: _markSeen,
              child: Text(l10n.updatesMarkSeen),
            )
          else
            PopupMenuItem<void>(
              onTap: _markUnseen,
              child: Text(l10n.updatesMarkUnseen),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final scheme = Theme.of(context).colorScheme;
    final isUnread = _isUnread;
    final copy = resolveUpdatesFeedRowCopy(
      title: widget.receipt.title,
      body: widget.receipt.body,
      presentationKey: widget.receipt.presentationKey,
      presentationPayloadJson: widget.receipt.presentationPayloadJson,
      l10n: l10n,
      headlineOverride: widget.headlineOverride,
      bodyOverride: widget.bodyOverride,
    );
    final glyph = updatesFeedGlyphFor(widget.receipt, tt);
    final localCreatedAt = widget.receipt.createdAt.toLocal();
    final ageLabel = compactRelativeTimeAgo(
      when: widget.receipt.createdAt,
      now: DateTime.now(),
      l10n: l10n,
    );
    final absoluteTime =
        '${dateFormatYMD(localCreatedAt)} ${timeFormatHm(localCreatedAt)}';
    final rowAction =
        widget.action ??
        (widget.receipt.isLiveObligation && widget.onSettle != null
            ? TenturaTextAction(
                label: l10n.updatesMarkDone,
                flushStart: true,
                onPressed: widget.onSettle,
              )
            : null);

    final profile = widget.actor == null
        ? null
        : profileWithContactOverlay(widget.actor!);
    final shownName = profile?.shownName.trim() ?? '';
    final headline = copy.headline;
    final showActorNamePrefix =
        shownName.isNotEmpty && shownName != headline.trim();

    final leading = profile != null
        ? _LeadingAvatar(profile: profile, unread: isUnread)
        : _LeadingGlyph(glyph: glyph, unread: isUnread);

    final bodyColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text.rich(
                TextSpan(
                  style: TenturaText.titleSmall(tt.text).copyWith(
                    fontWeight: isUnread ? FontWeight.w600 : FontWeight.w500,
                  ),
                  children: [
                    if (showActorNamePrefix) ...[
                      TextSpan(text: shownName),
                      TextSpan(
                        text: ' · ',
                        style: TenturaText.bodySmall(tt.textFaint),
                      ),
                    ],
                    TextSpan(text: headline),
                  ],
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
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
    );

    return Semantics(
      identifier: TestIds.updatesReceipt(widget.receipt.id),
      label: showActorNamePrefix ? '$shownName · $headline' : headline,
      button: true,
      child: Material(
        color: Colors.transparent,
        child: Padding(
          padding: tt.listRowPadding,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              SizedBox(width: tt.avatarTextGap),
              Expanded(
                child: _UpdatesFeedRowInteraction(
                  hovering: _hovering,
                  onHoverChanged: (hover) {
                    if (_hovering != hover) setState(() => _hovering = hover);
                  },
                  isUnread: isUnread,
                  markSeenLabel: l10n.updatesMarkSeen,
                  markUnseenLabel: l10n.updatesMarkUnseen,
                  onPrimaryTap: widget.onTap,
                  onMarkSeen: _markSeen,
                  onMarkUnseen: _markUnseen,
                  onShowMarkMenu: _showMarkMenu,
                  overlayColor: WidgetStateProperty.resolveWith((states) {
                    if (states.contains(WidgetState.pressed)) {
                      return scheme.onSurface.withValues(alpha: 0.06);
                    }
                    if (states.contains(WidgetState.hovered)) {
                      return scheme.onSurface.withValues(alpha: 0.03);
                    }
                    return null;
                  }),
                  child: bodyColumn,
                ),
              ),
              _UpdatesFeedRowOverflow(
                isUnread: isUnread,
                markSeenLabel: l10n.updatesMarkSeen,
                markUnseenLabel: l10n.updatesMarkUnseen,
                onMarkSeen: _markSeen,
                onMarkUnseen: _markUnseen,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Overflow + secondary-tap + hover toolbar for mark seen/unseen (never long-press alone).
class _UpdatesFeedRowInteraction extends StatelessWidget {
  const _UpdatesFeedRowInteraction({
    required this.child,
    required this.hovering,
    required this.onHoverChanged,
    required this.isUnread,
    required this.markSeenLabel,
    required this.markUnseenLabel,
    required this.onPrimaryTap,
    required this.onMarkSeen,
    required this.onMarkUnseen,
    required this.onShowMarkMenu,
    required this.overlayColor,
  });

  final Widget child;
  final bool hovering;
  final ValueChanged<bool> onHoverChanged;
  final bool isUnread;
  final String markSeenLabel;
  final String markUnseenLabel;
  final VoidCallback onPrimaryTap;
  final VoidCallback onMarkSeen;
  final VoidCallback onMarkUnseen;
  final VoidCallback onShowMarkMenu;
  final WidgetStateProperty<Color?> overlayColor;

  static const _touchOrStylus = {
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
  };

  void _toggleSeen() {
    if (isUnread) {
      onMarkSeen();
    } else {
      onMarkUnseen();
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content = RawGestureDetector(
      behavior: HitTestBehavior.opaque,
      gestures: <Type, GestureRecognizerFactory>{
        LongPressGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
              () => LongPressGestureRecognizer(supportedDevices: _touchOrStylus),
              (r) => r
                ..onLongPress = () {
                  unawaited(HapticFeedback.selectionClick());
                  onShowMarkMenu();
                },
            ),
      },
      child: InkWell(
        onTap: onPrimaryTap,
        overlayColor: overlayColor,
        child: child,
      ),
    );

    content = GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTap: _toggleSeen,
      child: content,
    );

    return MouseRegion(
      onEnter: (_) => onHoverChanged(true),
      onExit: (_) => onHoverChanged(false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          content,
          if (hovering)
            Positioned(
              top: 0,
              right: 4,
              child: _UpdatesFeedRowHoverToolbar(
                isUnread: isUnread,
                markSeenLabel: markSeenLabel,
                markUnseenLabel: markUnseenLabel,
                onMarkSeen: onMarkSeen,
                onMarkUnseen: onMarkUnseen,
                onMore: onShowMarkMenu,
              ),
            ),
        ],
      ),
    );
  }
}

class _UpdatesFeedRowHoverToolbar extends StatelessWidget {
  const _UpdatesFeedRowHoverToolbar({
    required this.isUnread,
    required this.markSeenLabel,
    required this.markUnseenLabel,
    required this.onMarkSeen,
    required this.onMarkUnseen,
    required this.onMore,
  });

  final bool isUnread;
  final String markSeenLabel;
  final String markUnseenLabel;
  final VoidCallback onMarkSeen;
  final VoidCallback onMarkUnseen;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      elevation: 2,
      color: scheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            constraints: const BoxConstraints(
              minWidth: kMinInteractiveDimension,
              minHeight: kMinInteractiveDimension,
            ),
            tooltip: isUnread ? markSeenLabel : markUnseenLabel,
            icon: Icon(
              isUnread ? Icons.visibility_outlined : Icons.visibility_off_outlined,
            ),
            onPressed: isUnread ? onMarkSeen : onMarkUnseen,
          ),
          IconButton(
            visualDensity: VisualDensity.compact,
            iconSize: 18,
            constraints: const BoxConstraints(
              minWidth: kMinInteractiveDimension,
              minHeight: kMinInteractiveDimension,
            ),
            tooltip: markUnseenLabel,
            icon: const Icon(Icons.more_horiz),
            onPressed: onMore,
          ),
        ],
      ),
    );
  }
}

class _UpdatesFeedRowOverflow extends StatelessWidget {
  const _UpdatesFeedRowOverflow({
    required this.isUnread,
    required this.markSeenLabel,
    required this.markUnseenLabel,
    required this.onMarkSeen,
    required this.onMarkUnseen,
  });

  final bool isUnread;
  final String markSeenLabel;
  final String markUnseenLabel;
  final VoidCallback onMarkSeen;
  final VoidCallback onMarkUnseen;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<void>(
      tooltip: MaterialLocalizations.of(context).showMenuTooltip,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(
        minWidth: kMinInteractiveDimension,
        minHeight: kMinInteractiveDimension,
      ),
      icon: const Icon(Icons.more_vert),
      itemBuilder: (context) => [
        if (isUnread)
          PopupMenuItem<void>(
            onTap: onMarkSeen,
            child: Text(markSeenLabel),
          )
        else
          PopupMenuItem<void>(
            onTap: onMarkUnseen,
            child: Text(markUnseenLabel),
          ),
      ],
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

class _LeadingAvatar extends StatelessWidget {
  const _LeadingAvatar({required this.profile, required this.unread});

  final Profile profile;
  final bool unread;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return SizedBox.square(
      dimension: tt.avatarSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          TenturaAvatar.medium(
            profile: profile,
            onTap: () => context.read<ScreenCubit>().showProfile(profile.id),
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
