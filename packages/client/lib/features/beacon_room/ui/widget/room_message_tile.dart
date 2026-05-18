import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:meta/meta.dart';

import 'package:tentura/app/router/root_router.dart';
import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_tokens.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/beacon_room/ui/bloc/room_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_poll_card.dart';
import 'package:tentura/features/beacon_room/ui/widget/reaction_senders_sheet.dart';
import 'package:tentura/features/beacon/ui/widget/coordination_ui.dart';
import 'package:tentura/features/beacon_view/ui/widget/self_aware_plain_mini_avatar.dart';
import 'package:tentura/features/coordination_item/ui/widget/item_card_in_room.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/avatar_rated.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/ui/widget/show_more_text.dart';
import 'package:readmore/readmore.dart';

/// Plan coordination items use the main beacon room, not per-item threads.
@visibleForTesting
bool planItemSuppressesItemDiscussion(CoordinationItem item) =>
    item.kind == CoordinationItemKind.plan;

VoidCallback? _linkedCoordinationItemOnTap(
  BuildContext context,
  CoordinationItem item,
) {
  if (planItemSuppressesItemDiscussion(item)) {
    return () {
      final cubit = context.read<RoomCubit>();
      if (cubit.state.threadItemId != null) return;
      cubit.prepareThreadScroll(
        messageId: item.threadAnchorMessageId,
        coordinationItemId: item.id,
      );
    };
  }
  return () => context.router.push(
        ItemDiscussionRoute(
          beaconId: item.beaconId,
          itemId: item.id,
          item: item,
        ),
      );
}

class RoomMessageTile extends StatelessWidget {
  const RoomMessageTile({
    required this.message,
    required this.myProfile,
    required this.onToggleReaction,
    this.onActionsPressed,
    this.onOpenFileAttachment,
    this.onVotePoll,
    this.previousMessage,
    this.nextMessage,
    this.breakGroupAbove = false,
    this.participants = const [],
    this.onScrollToPromoteSource,
    super.key,
  });

  final RoomMessage message;

  final RoomMessage? previousMessage;

  final RoomMessage? nextMessage;

  /// True when a date pill or unread band sits directly above this tile.
  final bool breakGroupAbove;

  /// Current user (for aligning / styling mine vs others').
  final Profile myProfile;

  /// Open actions for this message (tap / secondary tap on bubble).
  final void Function(RoomMessage message)? onActionsPressed;

  /// Jumps the chat viewport to the source message (promote pin bar).
  final void Function(String messageId)? onScrollToPromoteSource;

  /// Member-only file attachments (download + share flow).
  final Future<void> Function(RoomMessageAttachment attachment)?
  onOpenFileAttachment;

  final Future<void> Function(String messageId, String emoji) onToggleReaction;

  final Future<void> Function(
    String pollingId,
    List<String> variantIds, {
    int? score,
  })?
  onVotePoll;

  final List<BeaconParticipant> participants;

  /// Compact Telegram-style bar: server `system_payload` includes sourceMessageId.
  static bool isPromotePinNotification(RoomMessage m) {
    final src = m.sourceMessageId;
    final lid = m.linkedItemId;
    return src != null &&
        src.trim().isNotEmpty &&
        lid != null &&
        lid.trim().isNotEmpty;
  }

  static String _coordKindShortLabel(L10n l10n, CoordinationItemKind? k) =>
      switch (k) {
        CoordinationItemKind.plan => l10n.coordinationPlanCardLabel,
        CoordinationItemKind.ask => l10n.coordinationAskCardLabel,
        CoordinationItemKind.promise => l10n.coordinationPromiseCardLabel,
        CoordinationItemKind.blocker => l10n.coordinationBlockerCardLabel,
        CoordinationItemKind.resolution => l10n.coordinationResolutionCardLabel,
        null => l10n.coordinationItemCardTitle,
      };

  static bool _isCoordStateCard(RoomMessage m) {
    if (_isLinkedCoordSemantic(m)) return false;
    return m.semanticMarker == BeaconRoomSemanticMarker.blocker ||
        m.semanticMarker == BeaconRoomSemanticMarker.needInfo ||
        m.semanticMarker == BeaconRoomSemanticMarker.done;
  }

  static bool _isLinkedCoordSemantic(RoomMessage m) =>
      m.linkedItemId != null && m.linkedItemId!.trim().isNotEmpty;

  /// True when [a] and [b] must not share a Telegram-style avatar group.
  static bool _groupBreak(RoomMessage? a, RoomMessage? b) {
    if (a == null || b == null) return true;
    if (a.authorId != b.authorId) return true;
    if (_isCoordStateCard(a) || _isCoordStateCard(b)) return true;
    if (_isLinkedCoordSemantic(a) || _isLinkedCoordSemantic(b)) return true;
    final diff = b.createdAt.difference(a.createdAt).inMinutes.abs();
    return diff > 5;
  }

  String _semanticShortLabel(L10n l10n, int? marker) => switch (marker) {
    BeaconRoomSemanticMarker.updatePlan => l10n.beaconRoomSemanticPlan,
    BeaconRoomSemanticMarker.pinFactPublic => l10n.beaconRoomSemanticPublicFact,
    BeaconRoomSemanticMarker.pinFactPrivate => l10n.beaconRoomSemanticRoomFact,
    BeaconRoomSemanticMarker.participantStatusChanged =>
      l10n.beaconRoomSemanticParticipantStatus,
    BeaconRoomSemanticMarker.blocker => l10n.beaconRoomSemanticBlocker,
    BeaconRoomSemanticMarker.needInfo => l10n.beaconRoomSemanticNeedInfo,
    BeaconRoomSemanticMarker.done => l10n.beaconRoomSemanticDone,
    BeaconRoomSemanticMarker.poll => l10n.beaconRoomSemanticPoll,
    _ => marker == null ? '' : l10n.beaconRoomSemanticSystem,
  };

  static String _bodyForDisplay(RoomMessage message) {
    final raw = message.body.trim();
    if (raw.isNotEmpty) return raw;
    final sp = message.systemPayloadJson;
    if (sp == null || sp.isEmpty) return '';
    try {
      final map = jsonDecode(sp);
      if (map is! Map<String, dynamic>) return '';
      final plan = map['currentPlan'];
      if (plan is String && plan.trim().isNotEmpty) return plan.trim();
      final fact = map['factText'];
      if (fact is String && fact.trim().isNotEmpty) return fact.trim();
      final req = map['requestText'];
      if (req is String && req.trim().isNotEmpty) return req.trim();
    } on Object catch (_) {}
    return '';
  }

  static Set<String> _viewerReactionEmojiSet(RoomMessage m) {
    final raw = m.myReaction;
    if (raw == null || raw.trim().isEmpty) return {};
    return raw
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
  }

  static List<MapEntry<String, int>> _sortedReactionEntries(RoomMessage m) {
    final entries = m.reactionCounts.entries.toList()
      ..sort((a, b) {
        final countCmp = -a.value.compareTo(b.value);
        if (countCmp != 0) return countCmp;
        return a.key.compareTo(b.key);
      });
    return entries;
  }

  static String _formatAttachmentSize(int bytes) =>
      formatRoomAttachmentSize(bytes);

  static String _formatTime(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tt =
        theme.extension<TenturaTokens>() ??
        (theme.brightness == Brightness.dark
            ? TenturaTokens.dark
            : TenturaTokens.light);
    final isMine = message.authorId == myProfile.id;
    final semantic = _semanticShortLabel(l10n, message.semanticMarker);
    final display = _bodyForDisplay(message);
    final isStateCard = _isCoordStateCard(message);
    final linkedCoord = message.linkedCoordinationItem;
    final linkedEv = message.linkedEventKind;
    final linkedEventKind = linkedEv != null && linkedCoord != null
        ? CoordinationItemEventKind.fromInt(linkedEv)
        : null;
    final isGroupStart =
        breakGroupAbove || _groupBreak(previousMessage, message);
    final isGroupEnd = _groupBreak(message, nextMessage);

    final topPad = (isGroupStart ? tt.sectionGap : tt.rowGap / 2) / 2;
    final bottomPad = (isGroupEnd ? tt.sectionGap : tt.rowGap / 2) / 2;

    if (isPromotePinNotification(message)) {
      final srcId = message.sourceMessageId!;
      final kind = message.linkedCoordinationItem?.kind ??
          (message.linkedItemKind != null
              ? CoordinationItemKind.fromInt(message.linkedItemKind!)
              : null);
      final kindLabel = _coordKindShortLabel(l10n, kind);
      final pinTopPad = topPad / 2;
      final pinBottomPad = bottomPad / 2;
      final hInset = tt.screenHPadding;
      const innerV = 4.0;
      const innerH = 8.0;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          hInset,
          pinTopPad,
          hInset,
          pinBottomPad,
        ),
        child: BlocBuilder<ProfileCubit, ProfileState>(
          buildWhen: (p, c) => p.profile.id != c.profile.id,
          builder: (context, state) {
            final authorName = SelfUserHighlight.displayName(
              l10n,
              message.author,
              state.profile.id,
            );
            final line = l10n.beaconRoomPromotePinLine(authorName, kindLabel);
            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: onScrollToPromoteSource == null
                    ? null
                    : () => onScrollToPromoteSource!(srcId),
                borderRadius: BorderRadius.circular(tt.cardRadius),
                child: Semantics(
                  button: true,
                  label: line,
                  hint: l10n.beaconRoomPromotePinAccessibilityHint,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: innerH,
                      vertical: innerV,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.push_pin_outlined,
                          size: 14,
                          color: scheme.onSurfaceVariant,
                        ),
                        SizedBox(width: tt.iconTextGap / 2),
                        Flexible(
                          child: Text(
                            line,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w500,
                              height: 1.15,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    }

    final viewerReactions = _viewerReactionEmojiSet(message);

    String? authorHelpTypeWire;
    for (final p in participants) {
      if (p.userId == message.authorId) {
        authorHelpTypeWire = p.helpType;
        break;
      }
    }
    final authorCapabilityIcons = helpOfferTypeSlugs(authorHelpTypeWire)
        .take(4)
        .map(CapabilityTag.fromSlug)
        .whereType<CapabilityTag>()
        .map((t) => t.icon)
        .toList();

    final imageAttachments = message.attachments
        .where((a) => a.isImage && a.imageId.isNotEmpty)
        .toList();
    final fileAttachments = message.attachments.where((a) => a.isFile).toList();

    final handleToUserId = <String, String>{};
    for (final p in participants) {
      final h = p.handle.trim().toLowerCase();
      if (h.isNotEmpty) {
        handleToUserId[h] = p.userId;
      }
    }
    final mentionedIds = message.mentions.toSet();
    final mentionAnnotations = <Annotation>[
      Annotation(
        regExp: RegExp(
          '@[a-zA-Z0-9_]{$kUserHandleMinLength,$kUserHandleMaxLength}',
        ),
        spanBuilder: ({required text, textStyle}) {
          final handle = text.substring(1).toLowerCase();
          final userId = handleToUserId[handle];
          final isMentioned = userId != null && mentionedIds.contains(userId);
          if (!isMentioned) {
            return TextSpan(text: text, style: textStyle);
          }
          final isSelfMention = userId == myProfile.id;
          return TextSpan(
            text: text,
            style: textStyle?.copyWith(
              color: isSelfMention ? null : scheme.primary,
              backgroundColor: isSelfMention
                  ? scheme.tertiaryContainer.withValues(alpha: 0.8)
                  : null,
              fontWeight: isSelfMention ? FontWeight.w600 : FontWeight.w700,
            ),
          );
        },
      ),
    ];

    Widget reactionsAndTime() => Padding(
      padding: EdgeInsets.only(top: tt.rowGap / 2),
      child: SizedBox(
        width: double.infinity,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Wrap(
                spacing: kSpacingSmall,
                runSpacing: kSpacingSmall / 2,
                alignment: WrapAlignment.start,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final entry in _sortedReactionEntries(message))
                    InkWell(
                      key: ValueKey('${message.id}-re-${entry.key}'),
                      onTap: () => unawaited(
                        onToggleReaction(message.id, entry.key),
                      ),
                      onLongPress:
                          (message.reactors[entry.key]?.isNotEmpty ?? false)
                          ? () => unawaited(
                              showReactionSendersSheet(
                                context,
                                reactors: message.reactors,
                                reactionCounts: message.reactionCounts,
                                initialEmoji: entry.key,
                              ),
                            )
                          : null,
                      borderRadius: BorderRadius.circular(18),
                      child: Padding(
                        padding: kPaddingSmallH.add(
                          const EdgeInsets.symmetric(vertical: 6),
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: viewerReactions.contains(entry.key)
                                ? scheme.primaryContainer
                                : scheme.surfaceContainerHighest.withValues(
                                    alpha: 0.75,
                                  ),
                            borderRadius: BorderRadius.circular(999),
                            border: viewerReactions.contains(entry.key)
                                ? Border.all(color: scheme.primary)
                                : null,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: kSpacingSmall,
                              vertical: 2,
                            ),
                            child: _RoomReactionChipPill(
                              emoji: entry.key,
                              count: entry.value,
                              reactors:
                                  message.reactors[entry.key] ?? const [],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Padding(
              padding: EdgeInsets.only(
                left: tt.iconTextGap,
                bottom: 2,
              ),
              child: Text(
                [
                  _formatTime(message.createdAt),
                  if (message.editedAt != null) l10n.beaconRoomMessageEdited,
                ].join(' · '),
                style: theme.textTheme.labelSmall,
              ),
            ),
          ],
        ),
      ),
    );

    Widget coreColumn({required bool showNameHeader}) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showNameHeader)
          BlocBuilder<ProfileCubit, ProfileState>(
            buildWhen: (p, c) => p.profile.id != c.profile.id,
            builder: (context, state) {
              final isSelf = SelfUserHighlight.profileIsSelf(
                message.author,
                state.profile.id,
              );
              return Text(
                SelfUserHighlight.displayName(
                  l10n,
                  message.author,
                  state.profile.id,
                ),
                textAlign: TextAlign.start,
                style: SelfUserHighlight.nameStyle(
                  theme,
                  theme.textTheme.labelMedium,
                  isSelf,
                ),
              );
            },
          ),
        if (semantic.isNotEmpty && !isStateCard)
          Padding(
            padding: EdgeInsets.only(top: tt.iconTextGap / 2),
            child: Text(
              semantic,
              textAlign: TextAlign.start,
              style: theme.textTheme.labelMedium?.copyWith(
                color: scheme.tertiary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (linkedCoord != null && linkedEventKind != null)
          Padding(
            padding: EdgeInsets.only(top: tt.rowGap / 2),
            child: Align(
              alignment: Alignment.centerLeft,
              child: ItemCardInRoom(
                item: linkedCoord,
                eventKind: linkedEventKind,
                timelineAuthorId: message.authorId,
                onTap: _linkedCoordinationItemOnTap(
                  context,
                  linkedCoord,
                ),
              ),
            ),
          ),
        if (display.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: tt.rowGap / 2),
            child: ShowMoreText(
              display,
              style: ShowMoreText.buildTextStyle(context),
              colorClickableText: scheme.primary,
              annotations: mentionAnnotations,
              textAlign: TextAlign.start,
            ),
          ),
        if (imageAttachments.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: tt.rowGap / 2),
            child: RoomMessageInlineImageAlbum(
              attachments: imageAttachments,
            ),
          ),
        if (fileAttachments.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: tt.rowGap / 2),
            child: Wrap(
              spacing: kSpacingSmall,
              runSpacing: kSpacingSmall,
              alignment: WrapAlignment.start,
              children: [
                for (final a in fileAttachments)
                  ActionChip(
                    avatar: const Icon(
                      Icons.insert_drive_file_outlined,
                      size: 22,
                    ),
                    label: Text(
                      [
                        if (a.fileName.trim().isNotEmpty)
                          a.fileName
                        else
                          l10n.beaconRoomAttachmentUntitled,
                        if (_formatAttachmentSize(a.sizeBytes).isNotEmpty)
                          ' · ${_formatAttachmentSize(a.sizeBytes)}',
                      ].join(),
                    ),
                    onPressed: onOpenFileAttachment == null
                        ? null
                        : () => unawaited(onOpenFileAttachment!(a)),
                  ),
              ],
            ),
          ),
        if (message.linkedPollingId != null)
          Padding(
            padding: EdgeInsets.only(top: tt.rowGap / 2),
            child: RoomPollCard(
              poll:
                  RoomPollData.tryParse(message.pollDataJson) ??
                  RoomPollData(
                    id: message.linkedPollingId!,
                    question: '',
                    variants: const [],
                    totalVotes: 0,
                    myVariantIds: const [],
                  ),
              participants: participants,
              onVote: onVotePoll == null
                  ? null
                  : (variantIds, {score}) => unawaited(
                      onVotePoll!(
                        message.linkedPollingId!,
                        variantIds,
                        score: score,
                      ),
                    ),
            ),
          ),
        reactionsAndTime(),
      ],
    );

    Widget bubbleShell({
      required Widget child,
      required Color background,
      required Color borderColor,
    }) => Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(tt.cardRadius),
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: tt.cardPadding,
          child: child,
        ),
      ),
    );

    Widget wrapActions(Widget inner) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onActionsPressed == null ? null : () => onActionsPressed!(message),
      onSecondaryTap: onActionsPressed == null
          ? null
          : () => onActionsPressed!(message),
      child: inner,
    );

    if (isStateCard) {
      final stateBody = BlocBuilder<ProfileCubit, ProfileState>(
        buildWhen: (p, c) => p.profile.id != c.profile.id,
        builder: (context, state) {
          final displayName = SelfUserHighlight.displayName(
            l10n,
            message.author,
            state.profile.id,
          );
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                semantic.isEmpty
                    ? displayName
                    : l10n.beaconRoomStateCardInlineHeader(
                        displayName,
                        semantic,
                      ),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              coreColumn(showNameHeader: false),
            ],
          );
        },
      );

      return Padding(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          topPad,
          tt.screenHPadding,
          bottomPad,
        ),
        child: wrapActions(
          LayoutBuilder(
            builder: (context, c) {
              final cap = tt.contentMaxWidth ?? c.maxWidth;
              return Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: cap),
                  child: bubbleShell(
                    background: scheme.tertiaryContainer.withValues(
                      alpha: 0.45,
                    ),
                    borderColor: scheme.tertiary,
                    child: stateBody,
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    final bubbleBg = isMine ? tt.info.withValues(alpha: 0.18) : tt.surface;
    final bubbleBorder = isMine ? tt.skyBorder : tt.borderSubtle;

    final bubbleChild = bubbleShell(
      background: bubbleBg,
      borderColor: bubbleBorder,
      child: coreColumn(
        showNameHeader: !isMine && isGroupStart,
      ),
    );

    /// Same [Row] skeleton for mine and others: avatar gutter + gap + bubble so
    /// left/right bubble borders line up; bubble fills remaining width.
    final fullWidthBubble = LayoutBuilder(
      builder: (context, constraints) => SizedBox(
        width: constraints.maxWidth,
        child: wrapActions(bubbleChild),
      ),
    );

    // Others' bubbles: slight inset from the list edge so the card border
    // is not flush with the screen padding.
    final bubbleSlot = isMine
        ? fullWidthBubble
        : Padding(
            padding: const EdgeInsets.only(right: kSpacingSmall),
            child: fullWidthBubble,
          );

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        SizedBox(
          width: AvatarRated.sizeSmall + kSpacingSmall,
          child: isMine
              ? const SizedBox.shrink()
              : (isGroupEnd
                    ? GestureDetector(
                        onTap: () => context.read<ScreenCubit>().showProfile(
                          message.author.id,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelfAwarePlainMiniAvatar(profile: message.author),
                            if (authorCapabilityIcons.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              SizedBox(
                                width: AvatarRated.sizeSmall,
                                child: Wrap(
                                  alignment: WrapAlignment.center,
                                  spacing: 2,
                                  runSpacing: 2,
                                  children: [
                                    for (final icon in authorCapabilityIcons)
                                      Icon(
                                        icon,
                                        size: 12,
                                        color: scheme.onSurfaceVariant,
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                      )
                    : const SizedBox.shrink()),
        ),
        SizedBox(width: tt.avatarTextGap / 2),
        Expanded(child: bubbleSlot),
      ],
    );

    return Padding(
      padding: EdgeInsets.fromLTRB(
        tt.screenHPadding,
        topPad,
        tt.screenHPadding,
        bottomPad,
      ),
      child: row,
    );
  }
}

/// Emoji + overlapping reactor avatars (Telegram-style), or count fallback.
class _RoomReactionChipPill extends StatelessWidget {
  const _RoomReactionChipPill({
    required this.emoji,
    required this.count,
    required this.reactors,
  });

  final String emoji;

  final int count;

  final List<Profile> reactors;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          emoji,
          style: theme.textTheme.titleMedium?.copyWith(height: 1),
        ),
        const SizedBox(width: 4),
        if (reactors.isNotEmpty)
          _ReactorAvatarStrip(profiles: reactors)
        else
          Text(
            '$count',
            style: theme.textTheme.labelMedium?.copyWith(height: 1),
          ),
      ],
    );
  }
}

class _ReactorAvatarStrip extends StatelessWidget {
  const _ReactorAvatarStrip({required this.profiles});

  final List<Profile> profiles;

  static const double _size = 16;

  static const double _overlap = 4;

  static const int _maxVisible = 3;

  static const double _step = _size - _overlap;

  /// Stack height: room for [AvatarRated] plus up to 2px ring (self highlight).
  static const double _stackCross = _size + 4;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = profiles.length;
    if (n == 0) {
      return const SizedBox.shrink();
    }

    final overflow = n > _maxVisible ? n - _maxVisible : 0;
    final visible = profiles.take(_maxVisible).toList();
    final extraSlots = overflow > 0 ? 1 : 0;
    final width = _size + (visible.length + extraSlots - 1) * _step;

    return BlocBuilder<ProfileCubit, ProfileState>(
      buildWhen: (p, c) => p.profile.id != c.profile.id,
      builder: (context, state) {
        final theme = Theme.of(context);
        final ringColor = scheme.outlineVariant;

        return SizedBox(
          width: width,
          height: _stackCross,
          child: Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < visible.length; i++)
                Positioned(
                  left: i * _step,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color:
                              SelfUserHighlight.profileIsSelf(
                                visible[i],
                                state.profile.id,
                              )
                              ? scheme.primary
                              : ringColor,
                          width:
                              SelfUserHighlight.profileIsSelf(
                                visible[i],
                                state.profile.id,
                              )
                              ? 2
                              : 1,
                        ),
                      ),
                      child: AvatarRated(
                        profile: visible[i],
                        withRating: false,
                        size: _size,
                      ),
                    ),
                  ),
                ),
              if (overflow > 0)
                Positioned(
                  left: visible.length * _step,
                  top: 0,
                  bottom: 0,
                  child: Align(
                    child: Container(
                      width: _size,
                      height: _size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: scheme.surfaceContainerHigh,
                        border: Border.all(color: ringColor),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '+$overflow',
                        style: theme.textTheme.labelMedium!.copyWith(
                          fontWeight: FontWeight.w700,
                          color: scheme.onSurfaceVariant,
                          height: 1,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
