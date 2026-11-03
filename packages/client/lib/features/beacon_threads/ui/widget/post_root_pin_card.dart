import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/features/beacon_threads/domain/room_host.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_file_attachment_open.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_message_trailing_meta_layout.dart';
import 'package:tentura/features/post_view/ui/post_remaining_label.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/relative_time.dart';

/// Expanded or collapsed Post root card for the Post room, composer preview,
/// and recipient-picker header (#248). Collapsed matches the legacy pinned strip.
class PostRootPinCard extends StatelessWidget {
  const PostRootPinCard({
    required this.pin,
    required this.collapsed,
    required this.onTap,
    required this.now,
    this.rootMessage,
    this.draftExcerpt = '',
    this.author,
    this.expiresAt,
    this.archived = false,
    this.peopleCount,
    this.replyCount,
    this.forwardPolicyOpen = true,
    this.editorBody,
    this.editorLifetimeLabel = '',
    super.key,
  });

  final RoomPostRootPin pin;
  final bool collapsed;
  final VoidCallback? onTap;
  final DateTime now;
  final RoomMessage? rootMessage;
  final String draftExcerpt;
  final Profile? author;
  final DateTime? expiresAt;
  final bool archived;
  final int? peopleCount;
  final int? replyCount;
  final bool forwardPolicyOpen;
  final Widget? editorBody;
  final String editorLifetimeLabel;

  bool get _isEditor => editorBody != null;

  bool get _showExpanded => !_isEditor && !collapsed && rootMessage != null;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    Widget body;
    if (_isEditor) {
      body = _EditorBody(
        author: author!,
        lifetimeLabel: editorLifetimeLabel,
        body: editorBody!,
      );
    } else {
      final collapsed = _CollapsedBody(
        pin: pin,
        excerpt: _collapsedExcerpt(),
      );
      final expanded = rootMessage == null
          ? collapsed
          : _ExpandedBody(
              pin: pin,
              message: rootMessage!,
              author: author ?? rootMessage!.author,
              now: now,
              expiresAt: expiresAt,
              archived: archived,
              peopleCount: peopleCount,
              replyCount: replyCount,
              forwardPolicyOpen: forwardPolicyOpen,
            );
      body = AnimatedSize(
        duration: reduceMotion
            ? Duration.zero
            : const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        alignment: Alignment.topCenter,
        child: _showExpanded
            ? KeyedSubtree(
                key: const Key('PostRootPinCard.expanded'),
                child: expanded,
              )
            : KeyedSubtree(
                key: const Key('PostRootPinCard.collapsed'),
                child: collapsed,
              ),
      );
    }

    final card = Material(
      color: tt.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(tt.cardRadius),
        side: BorderSide(color: tt.borderSubtle),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: tt.cardPadding,
          child: body,
        ),
      ),
    );

    if (_isEditor) return card;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        tt.rowGap,
        tt.screenHPadding,
        tt.rowGap,
      ),
      child: card,
    );
  }

  String _collapsedExcerpt() {
    if (draftExcerpt.trim().isNotEmpty) return draftExcerpt.trim();
    if (pin.excerpt.isNotEmpty) return pin.excerpt;
    return rootMessage?.body.trim() ?? '';
  }
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.author,
    required this.lifetimeLabel,
    required this.body,
  });

  final Profile author;
  final String lifetimeLabel;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final tt = context.tt;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TenturaAvatar.small(profile: author),
            SizedBox(width: tt.avatarTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    author.shownName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TenturaText.titleSmall(tt.text),
                  ),
                  if (lifetimeLabel.isNotEmpty)
                    Text(
                      lifetimeLabel,
                      style: TenturaText.bodySmall(tt.textMuted),
                    ),
                ],
              ),
            ),
          ],
        ),
        SizedBox(height: tt.rowGap),
        body,
      ],
    );
  }
}

class _CollapsedBody extends StatelessWidget {
  const _CollapsedBody({required this.pin, required this.excerpt});

  final RoomPostRootPin pin;
  final String excerpt;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final forwardedLine = _forwardedLine(l10n, pin);
    final showExcerpt = excerpt.isNotEmpty && pin.startedBy.isEmpty;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.push_pin_outlined, size: tt.iconSize),
        SizedBox(width: tt.iconTextGap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showExcerpt)
                Text(
                  excerpt,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.bodySmall(tt.text),
                ),
              if (forwardedLine != null)
                Text(
                  forwardedLine,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TenturaText.bodySmall(tt.textMuted),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpandedBody extends StatelessWidget {
  const _ExpandedBody({
    required this.pin,
    required this.message,
    required this.author,
    required this.now,
    this.expiresAt,
    this.archived = false,
    this.peopleCount,
    this.replyCount,
    this.forwardPolicyOpen = true,
  });

  final RoomPostRootPin pin;
  final RoomMessage message;
  final Profile author;
  final DateTime now;
  final DateTime? expiresAt;
  final bool archived;
  final int? peopleCount;
  final int? replyCount;
  final bool forwardPolicyOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final tt = context.tt;
    final forwardedLine = _forwardedLine(l10n, pin);
    final age = cardRelativeAge(when: message.createdAt, now: now, l10n: l10n);
    final body = message.body.trim();
    final metaStyle = TenturaText.bodySmall(tt.textMuted);
    final lifetime = postLifetimeLineForDeadline(
      l10n,
      now: now,
      expiresAt: expiresAt,
      archived: archived,
    );
    final metrics = computeTrailingMetaMetrics(
      dateLine: '',
      metaStyle: metaStyle,
      trailingGapH: 0,
      trailingGapV: 0,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TenturaAvatar.small(profile: author),
            SizedBox(width: tt.avatarTextGap),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          author.shownName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TenturaText.titleSmall(tt.text),
                        ),
                      ),
                      if (lifetime.isNotEmpty) ...[
                        SizedBox(width: tt.tightGap),
                        Flexible(
                          child: Text(
                            lifetime,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: metaStyle,
                          ),
                        ),
                      ],
                    ],
                  ),
                  Text(age, style: metaStyle),
                ],
              ),
            ),
          ],
        ),
        if (body.isNotEmpty) ...[
          SizedBox(height: tt.rowGap),
          RoomMessageTextBody(
            display: body,
            dateLine: '',
            bodyStyle: TenturaText.bodyMedium(tt.text),
            metaStyle: metaStyle,
            metrics: metrics,
          ),
        ],
        if (message.attachments.isNotEmpty) ...[
          SizedBox(height: tt.rowGap),
          RoomPinnedStyleAttachments(
            attachments: message.attachments,
            l10n: l10n,
            onOpenFileAttachment: (a) =>
                openRoomFileAttachment(context, l10n, a),
          ),
        ],
        if (forwardedLine != null) ...[
          SizedBox(height: tt.rowGap),
          Text(forwardedLine, style: metaStyle),
        ],
        if (peopleCount != null && replyCount != null) ...[
          SizedBox(height: tt.rowGap),
          Text(
            forwardPolicyOpen
                ? l10n.postCardMetaCanShare(peopleCount!, replyCount!)
                : l10n.postCardMetaInviteOnly(peopleCount!, replyCount!),
            style: metaStyle,
          ),
        ],
      ],
    );
  }
}

String? _forwardedLine(L10n l10n, RoomPostRootPin pin) {
  if (pin.startedBy.isNotEmpty) {
    return pin.forwardNote.isEmpty
        ? l10n.postStartedByLine(pin.startedBy)
        : l10n.postStartedByLineWithNote(pin.startedBy, pin.forwardNote);
  }
  if (pin.forwardedBy.isEmpty) return null;
  return pin.forwardNote.isEmpty
      ? l10n.postForwardedByLineNoNote(pin.forwardedBy)
      : l10n.postForwardedByLine(pin.forwardedBy, pin.forwardNote);
}

/// Collapsed draft preview for the post composer recipient step.
class PostRootDraftPreviewCard extends StatelessWidget {
  const PostRootDraftPreviewCard({
    required this.excerpt,
    required this.onTap,
    super.key,
  });

  final String excerpt;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final pin = RoomPostRootPin(messageId: '', excerpt: excerpt);
    return PostRootPinCard(
      pin: pin,
      collapsed: true,
      onTap: onTap,
      now: DateTime.now(),
      draftExcerpt: excerpt,
    );
  }
}
