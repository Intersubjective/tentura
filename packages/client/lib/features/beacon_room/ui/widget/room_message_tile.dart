import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:tentura/app/router/root_router.dart';
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
import 'package:tentura/design_system/components/tentura_avatar.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/features/beacon_room/ui/coordination_room_navigation.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/coordination_item_presenter.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_bubble_measure.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_text_body.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_message_trailing_meta_layout.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

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
    this.onOpenCoordinationItem,
    this.hideCoordinationLifecycleFooter = false,
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

  /// Opens item thread or scrolls to plan anchor from footer / inline card.
  final void Function(CoordinationItem item)? onOpenCoordinationItem;

  /// True in item discussion thread (no lifecycle footer rows).
  final bool hideCoordinationLifecycleFooter;

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

  /// Fact-pin notify row: semantic fact marker + scroll target in payload.
  static bool isFactPinNotification(RoomMessage m) {
    final marker = m.semanticMarker;
    if (marker != BeaconRoomSemanticMarker.pinFactPublic &&
        marker != BeaconRoomSemanticMarker.pinFactPrivate) {
      return false;
    }
    final src = m.sourceMessageId;
    return src != null && src.trim().isNotEmpty;
  }

  /// Centered coordination timeline row pointing at a source message.
  @visibleForTesting
  static bool isCoordinationTimelineNotifyRow(RoomMessage m) {
    if (isFactPinNotification(m)) return false;
    if (isPlanAnnounceBar(m)) return false;
    final lid = m.linkedItemId;
    final ev = m.linkedEventKind;
    if (lid == null || lid.trim().isEmpty || ev == null) return false;

    final src = m.sourceMessageId?.trim();
    if (src != null && src.isNotEmpty) {
      return m.id != src;
    }

    final anchor = m.linkedItemLinkedMessageId?.trim();
    if (anchor == null || anchor.isEmpty) return false;
    if (m.id == anchor) return false;
    return ev != CoordinationItemEventKind.created.value;
  }

  /// Scroll target for [isCoordinationTimelineNotifyRow] (payload or enrichment).
  @visibleForTesting
  static String? coordinationTimelineAnchorMessageId(RoomMessage m) {
    final src = m.sourceMessageId?.trim();
    if (src != null && src.isNotEmpty) return src;
    final anchor = m.linkedItemLinkedMessageId?.trim();
    if (anchor != null && anchor.isNotEmpty) return anchor;
    return null;
  }

  /// @deprecated Use [isCoordinationTimelineNotifyRow].
  static bool isPromotePinNotification(RoomMessage m) =>
      isCoordinationTimelineNotifyRow(m) &&
      m.linkedEventKind == CoordinationItemEventKind.created.value;

  /// Plan updated from room menu (no linked chat message).
  static bool isPlanAnnounceBar(RoomMessage m) {
    if (m.linkedItemKind != CoordinationItemKind.plan.value) return false;
    if (m.linkedEventKind != CoordinationItemEventKind.created.value) {
      return false;
    }
    if (m.sourceMessageId != null) return false;
    if (m.semanticMarker != null) return false;
    return m.body.trim().isEmpty;
  }

  static bool showMarkDoneFooter(RoomMessage m) =>
      m.semanticMarker == BeaconRoomSemanticMarker.done;

  /// Bottom-row coordination indicator (replaces inline coordination plaques).
  @visibleForTesting
  static bool showCoordinationItemFooter(RoomMessage m) {
    if (isPlanAnnounceBar(m)) return false;
    if (isCoordinationTimelineNotifyRow(m)) return false;
    if (isFactPinNotification(m)) return false;
    final ev = m.linkedEventKind;
    if (m.linkedItemId == null || m.linkedItemId!.trim().isEmpty) {
      return false;
    }
    if (ev == null) return false;
    return m.linkedCoordinationItem != null;
  }

  /// @deprecated Use [showCoordinationItemFooter].
  static bool showLifecycleFooter(RoomMessage m) =>
      showCoordinationItemFooter(m) && m.isPromotedSourceMessage;

  @visibleForTesting
  static bool isThreadEntryKind(CoordinationItemKind kind) =>
      kind == CoordinationItemKind.ask ||
      kind == CoordinationItemKind.promise ||
      kind == CoordinationItemKind.blocker;

  /// Ask / promise / blocker marks stay vivid on cards so thread access matches open items.
  @visibleForTesting
  static Color threadMarkAccent(TenturaTokens tt, CoordinationItemKind kind) =>
      coordinationItemColor(tt, kind, CoordinationItemStatus.open);

  static Profile? profileForUserId(
    String userId,
    List<BeaconParticipant> participants,
  ) {
    if (userId.isEmpty) return null;
    for (final p in participants) {
      if (p.userId == userId) {
        return Profile(
          id: p.userId,
          displayName: p.userTitle,
          image: p.userHasPicture && p.userImageId.isNotEmpty
              ? ImageEntity(
                  id: p.userImageId,
                  authorId: p.userId,
                  blurHash: p.userBlurHash,
                  height: p.userPicHeight,
                  width: p.userPicWidth,
                )
              : null,
        );
      }
    }
    return Profile(id: userId);
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

  static bool _isLinkedCoordSemantic(RoomMessage m) =>
      m.linkedItemId != null && m.linkedItemId!.trim().isNotEmpty;

  /// True when [a] and [b] must not share a Telegram-style avatar group.
  static bool _groupBreak(RoomMessage? a, RoomMessage? b) {
    if (a == null || b == null) return true;
    if (a.authorId != b.authorId) return true;
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
      final line = map['currentLine'] ?? map['currentPlan'];
      if (line is String && line.trim().isNotEmpty) return line.trim();
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

  static String _formatMessageTime(DateTime t) => _formatTime(t);

  VoidCallback? _coordinationItemTap(
    BuildContext context,
    CoordinationItem item,
  ) {
    final open = onOpenCoordinationItem;
    if (open != null) {
      return () => open(item);
    }
    return _linkedCoordinationItemOnTap(context, item);
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
    final showCoordinationFooter = !hideCoordinationLifecycleFooter &&
        showCoordinationItemFooter(message);
    final showMarkDone = showMarkDoneFooter(message);

    if (isFactPinNotification(message)) {
      final srcId = message.sourceMessageId!;
      final visibilityLabel =
          message.semanticMarker == BeaconRoomSemanticMarker.pinFactPublic
          ? l10n.beaconRoomSemanticPublicFact
          : l10n.beaconRoomSemanticRoomFact;
      return _CenteredTimelineBar(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          topPad / 2,
          tt.screenHPadding,
          bottomPad / 2,
        ),
        icon: Icons.fact_check_outlined,
        lineBuilder: (authorName) =>
            l10n.beaconRoomFactPinLine(authorName, visibilityLabel),
        author: message.author,
        onTap: onScrollToPromoteSource == null
            ? null
            : () => onScrollToPromoteSource!(srcId),
        accessibilityHint: l10n.beaconRoomPromotePinAccessibilityHint,
        borderRadius: tt.cardRadius,
        scheme: scheme,
        theme: theme,
        iconTextGap: tt.iconTextGap,
      );
    }

    if (isCoordinationTimelineNotifyRow(message)) {
      final srcId = coordinationTimelineAnchorMessageId(message);
      if (srcId != null) {
        final kind = message.linkedCoordinationItem?.kind ??
            (message.linkedItemKind != null
                ? CoordinationItemKind.fromInt(message.linkedItemKind!)
                : null);
        final eventKind = message.linkedEventKind != null
            ? CoordinationItemEventKind.fromInt(message.linkedEventKind!)
            : null;
        if (eventKind == null) {
          return const SizedBox.shrink();
        }
        final isPlanStep = message.linkedCoordinationItem?.isPlanStep ?? false;
        final isCreated = eventKind == CoordinationItemEventKind.created;
        return _CenteredTimelineBar(
          padding: EdgeInsets.fromLTRB(
            tt.screenHPadding,
            topPad / 2,
            tt.screenHPadding,
            bottomPad / 2,
          ),
          icon: Icons.push_pin_outlined,
          leading: isCreated
              ? null
              : coordinationCompoundEventIcon(
                  kind: kind ?? CoordinationItemKind.ask,
                  eventKind: eventKind,
                  isPlanStep: isPlanStep,
                  tt: tt,
                  size: 14,
                ),
          lineBuilder: (authorName) {
            if (eventKind == CoordinationItemEventKind.created) {
              return l10n.beaconRoomPromotePinLine(
                authorName,
                _coordKindShortLabel(l10n, kind),
              );
            }
            if (kind == null) return authorName;
            return '$authorName · ${coordinationEventTimelineLabel(l10n, kind, eventKind, isPlanStep: isPlanStep)}';
          },
          author: message.author,
          onTap: onScrollToPromoteSource == null
              ? null
              : () => onScrollToPromoteSource!(srcId),
          accessibilityHint: l10n.beaconRoomPromotePinAccessibilityHint,
          borderRadius: tt.cardRadius,
          scheme: scheme,
          theme: theme,
          iconTextGap: tt.iconTextGap,
        );
      }
    }

    if (isPlanAnnounceBar(message)) {
      final title = (message.linkedItemTitle ?? '').trim();
      return _CenteredTimelineBar(
        padding: EdgeInsets.fromLTRB(
          tt.screenHPadding,
          topPad / 2,
          tt.screenHPadding,
          bottomPad / 2,
        ),
        icon: Icons.edit_note_outlined,
        lineBuilder: (authorName) => title.isEmpty
            ? l10n.beaconRoomPlanAnnounceLine(authorName)
            : l10n.beaconRoomPlanAnnounceLineWithTitle(authorName, title),
        author: message.author,
        onTap: null,
        accessibilityHint: null,
        borderRadius: tt.cardRadius,
        scheme: scheme,
        theme: theme,
        iconTextGap: tt.iconTextGap,
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
    final mentionAnnotations = buildRoomMessageMentionAnnotations(
      handleToUserId: handleToUserId,
      mentionedIds: mentionedIds,
      selfUserId: myProfile.id,
      mentionColor: scheme.primary,
      selfMentionBackground: scheme.tertiaryContainer.withValues(alpha: 0.8),
    );

    final editedSuffix =
        message.editedAt != null ? l10n.beaconRoomMessageEdited : null;
    final dateLine = [
      _formatMessageTime(message.editedAt ?? message.createdAt),
      ?editedSuffix,
    ].join(' · ');
    final useInlineMeta = shouldUseInlineTrailingMeta(
      hasDisplayText: display.isNotEmpty,
      reactionCounts: message.reactionCounts,
    );
    final hasMediaOrPoll =
        imageAttachments.isNotEmpty ||
        fileAttachments.isNotEmpty ||
        message.linkedPollingId != null;
    final bodyStyle = ShowMoreText.buildTextStyle(context);
    final metaStyle = theme.textTheme.labelSmall ?? const TextStyle();
    final trailingGap = tt.iconTextGap / 2;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final trailingMetrics = useInlineMeta
        ? computeTrailingMetaMetrics(
            dateLine: dateLine,
            metaStyle: metaStyle,
            bodyStyle: bodyStyle,
            trailingGap: trailingGap,
            textDirection: textDirection,
            textScaler: textScaler,
          )
        : null;

    Widget reactionsAndTime() => _MessageLifecycleFooter(
      message: message,
      participants: participants,
      linkedCoord: linkedCoord,
      viewerReactions: viewerReactions,
      tokens: tt,
      scheme: scheme,
      textTheme: theme.textTheme,
      l10n: l10n,
      showCoordinationFooter: showCoordinationFooter,
      linkedEventKind: linkedEventKind,
      showMarkDone: showMarkDone,
      onToggleReaction: onToggleReaction,
      onOpenItem: linkedCoord == null
          ? null
          : _coordinationItemTap(context, linkedCoord),
      editedSuffix: editedSuffix,
      hideTimestamp: useInlineMeta,
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
        if (semantic.isNotEmpty &&
            !showCoordinationFooter &&
            message.semanticMarker != BeaconRoomSemanticMarker.done)
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
        if (display.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: tt.rowGap / 2),
            child: useInlineMeta && trailingMetrics != null
                ? RoomMessageTextBody(
                    display: display,
                    dateLine: dateLine,
                    bodyStyle: bodyStyle,
                    metaStyle: metaStyle,
                    metrics: trailingMetrics,
                    mentionAnnotations: mentionAnnotations,
                  )
                : ShowMoreText(
                    display,
                    style: bodyStyle,
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

    final bubbleBg = isMine ? tt.info.withValues(alpha: 0.18) : tt.surface;
    final bubbleBorder = isMine ? tt.skyBorder : tt.borderSubtle;

    final bubbleChild = bubbleShell(
      background: bubbleBg,
      borderColor: bubbleBorder,
      child: coreColumn(
        showNameHeader: !isMine && isGroupStart,
      ),
    );

    final hasReactions = message.reactionCounts.isNotEmpty;
    final hasFooterContent =
        (showCoordinationFooter && linkedCoord != null) || showMarkDone;
    final shouldHug = shouldHugBubbleWidth(
      hasMediaOrPoll: hasMediaOrPoll,
      hasDisplayText: display.isNotEmpty,
      hasReactions: hasReactions,
      hasFooterContent: hasFooterContent,
    );

    final measuredBubble = LayoutBuilder(
      builder: (context, constraints) {
        final contentCap = shouldHug
            ? constraints.maxWidth * kRoomMessageBubbleMaxWidthFraction
            : constraints.maxWidth;
        final cardPaddingH = tt.cardPadding.horizontal;

        double? tightTextWidth;
        if (shouldHug) {
          if (display.isNotEmpty) {
            final bodySpan = buildRoomMessageAnnotatedBodySpan(
              data: display,
              textStyle: bodyStyle,
              annotations: mentionAnnotations,
            );
            if (useInlineMeta && trailingMetrics != null) {
              tightTextWidth = measureTightBodyWidthWithTrailingReserve(
                bodySpan: bodySpan,
                trailingReserveWidth: trailingMetrics.reserveWidth,
                maxWidth: contentCap,
                textDirection: textDirection,
                textScaler: textScaler,
              );
            } else {
              tightTextWidth = measureTightTextWidth(
                span: bodySpan,
                maxWidth: contentCap,
                textDirection: textDirection,
                textScaler: textScaler,
              );
            }
          } else {
            tightTextWidth = 0;
          }

          if (!isMine && isGroupStart) {
            final namePainter = TextPainter(
              text: TextSpan(
                text: message.author.shownName,
                style: theme.textTheme.labelMedium,
              ),
              textDirection: textDirection,
              textScaler: textScaler,
            )..layout();
            if (namePainter.width > tightTextWidth) {
              tightTextWidth = namePainter.width;
            }
          }

          final footerGap = tt.iconTextGap / 4;
          final lifecycleLabelStyle = theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
          );
          final lifecycleTimeStyle = theme.textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          );
          final hasItemTap = linkedCoord != null;
          var footerMinWidth = 0.0;

          if (showCoordinationFooter && linkedCoord != null) {
            final promotionDate =
                message.linkedItemUpdatedAt ?? message.linkedItemCreatedAt;
            if (message.isPromotedSourceMessage &&
                promotionDate != null &&
                lifecycleLabelStyle != null &&
                lifecycleTimeStyle != null) {
              footerMinWidth = measureLifecycleTapRowMinWidth(
                label: _coordKindShortLabel(l10n, linkedCoord.kind),
                time: _formatMessageTime(promotionDate),
                labelStyle: lifecycleLabelStyle,
                timeStyle: lifecycleTimeStyle,
                itemGap: footerGap,
                showChevron: hasItemTap,
                textDirection: textDirection,
                textScaler: textScaler,
              );
            } else if (!message.isPromotedSourceMessage &&
                linkedEventKind != null &&
                lifecycleLabelStyle != null &&
                lifecycleTimeStyle != null) {
              final at = promotionDate ?? message.createdAt;
              footerMinWidth = measureLifecycleTapRowMinWidth(
                label: coordinationEventTimelineLabel(
                  l10n,
                  linkedCoord.kind,
                  linkedEventKind,
                  isPlanStep: linkedCoord.isPlanStep,
                ),
                time: _formatMessageTime(at),
                labelStyle: lifecycleLabelStyle,
                timeStyle: lifecycleTimeStyle,
                itemGap: footerGap,
                showChevron: hasItemTap,
                textDirection: textDirection,
                textScaler: textScaler,
              );
            }

            final status = message.linkedItemStatus;
            final isTerminal = status == CoordinationItemStatus.resolved.value ||
                status == CoordinationItemStatus.cancelled.value ||
                status == CoordinationItemStatus.superseded.value;
            final skipResolutionWidth =
                message.isPromotedSourceMessage &&
                promotionDate != null &&
                RoomMessageTile.isThreadEntryKind(linkedCoord.kind);
            if (message.isPromotedSourceMessage &&
                isTerminal &&
                !skipResolutionWidth &&
                lifecycleLabelStyle != null &&
                lifecycleTimeStyle != null) {
              final last = message.lastStatusEvent;
              final eventKind = last != null
                  ? CoordinationItemEventKind.fromInt(last.eventKind)
                  : null;
              final at = last?.at ??
                  message.linkedItemResolvedAt ??
                  message.linkedItemUpdatedAt;
              if (eventKind != null && at != null) {
                final resolutionWidth = measureLifecycleTapRowMinWidth(
                  label: coordinationEventTimelineLabel(
                    l10n,
                    linkedCoord.kind,
                    eventKind,
                    isPlanStep: linkedCoord.isPlanStep,
                  ),
                  time: _formatMessageTime(at),
                  labelStyle: lifecycleLabelStyle,
                  timeStyle: lifecycleTimeStyle,
                  itemGap: footerGap,
                  showChevron: hasItemTap,
                  textDirection: textDirection,
                  textScaler: textScaler,
                );
                if (resolutionWidth > footerMinWidth) {
                  footerMinWidth = resolutionWidth;
                }
              }
            }
          }

          if (showMarkDone && lifecycleLabelStyle != null) {
            final markDoneWidth = measureMarkDoneRowMinWidth(
              label: l10n.beaconRoomSemanticDone,
              labelStyle: lifecycleLabelStyle.copyWith(color: tt.good),
              itemGap: footerGap,
              textDirection: textDirection,
              textScaler: textScaler,
            );
            if (markDoneWidth > footerMinWidth) {
              footerMinWidth = markDoneWidth;
            }
          }

          if (footerMinWidth > tightTextWidth) {
            tightTextWidth = footerMinWidth;
          }

          if (hasReactions) {
            final emojiStyle =
                theme.textTheme.titleMedium?.copyWith(height: 1) ??
                const TextStyle();
            final countStyle =
                theme.textTheme.labelMedium?.copyWith(height: 1) ??
                const TextStyle();
            final reactorCountsByEmoji = {
              for (final entry in message.reactionCounts.entries)
                entry.key: message.reactors[entry.key]?.length ?? 0,
            };
            tightTextWidth = ensureHugWidthFitsReactionFooter(
              contentWidth: tightTextWidth,
              reactionEntries: _sortedReactionEntries(message),
              reactorCountsByEmoji: reactorCountsByEmoji,
              dateLine: dateLine,
              emojiStyle: emojiStyle,
              countStyle: countStyle,
              timeStyle: metaStyle,
              chipSpacing: kSpacingSmall,
              trailingGap: trailingGap,
              textDirection: textDirection,
              textScaler: textScaler,
            );
          }
        }

        var hugContentCap = contentCap;
        if (shouldHug && tightTextWidth != null && tightTextWidth > hugContentCap) {
          hugContentCap = tightTextWidth.clamp(0, constraints.maxWidth);
        }

        final bubbleWidth = measureBubble(
          contentMaxWidth: hugContentCap,
          cardPaddingH: cardPaddingH,
          tightTextWidth: shouldHug ? tightTextWidth : null,
          hasMediaOrPoll: hasMediaOrPoll,
        ).innerWidth;

        return Align(
          alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
          child: SizedBox(
            width: bubbleWidth,
            child: wrapActions(bubbleChild),
          ),
        );
      },
    );

    final bubbleSlot = Padding(
      padding: EdgeInsets.only(
        right: isMine ? 0 : kSpacingSmall,
        left: isMine ? kSpacingSmall : 0,
      ),
      child: measuredBubble,
    );

    final row = isMine
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: bubbleSlot,
                ),
              ),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: kTenturaAvatarDefaultMedium + kSpacingSmall,
                child: isGroupEnd
                    ? GestureDetector(
                        onTap: () => context.read<ScreenCubit>().showProfile(
                          message.author.id,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SelfAwareAvatar.medium(
                              profile: message.author,
                            ),
                            if (authorCapabilityIcons.isNotEmpty) ...[
                              const SizedBox(height: 1),
                              SizedBox(
                                width: kTenturaAvatarDefaultMedium,
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
                    : const SizedBox.shrink(),
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

/// Centered in-chat system / promote / fact / plan announce bar.
class _CenteredTimelineBar extends StatelessWidget {
  const _CenteredTimelineBar({
    required this.padding,
    required this.icon,
    required this.lineBuilder,
    required this.author,
    required this.onTap,
    required this.accessibilityHint,
    required this.borderRadius,
    required this.scheme,
    required this.theme,
    required this.iconTextGap,
    this.leading,
  });

  final EdgeInsets padding;
  final IconData icon;
  final Widget? leading;
  final String Function(String authorName) lineBuilder;
  final Profile author;
  final VoidCallback? onTap;
  final String? accessibilityHint;
  final double borderRadius;
  final ColorScheme scheme;
  final ThemeData theme;
  final double iconTextGap;

  static const double _innerV = 4;
  static const double _innerH = 8;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: BlocBuilder<ProfileCubit, ProfileState>(
        buildWhen: (p, c) => p.profile.id != c.profile.id,
        builder: (context, state) {
          final l10n = L10n.of(context)!;
          final authorName = SelfUserHighlight.displayName(
            l10n,
            author,
            state.profile.id,
          );
          final line = lineBuilder(authorName);
          final content = Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: _innerH,
              vertical: _innerV,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                leading ??
                    Icon(
                      icon,
                      size: 14,
                      color: scheme.onSurfaceVariant,
                    ),
                SizedBox(width: iconTextGap / 2),
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
          );
          if (onTap == null) {
            return Semantics(label: line, child: content);
          }
          return Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(borderRadius),
              child: Semantics(
                button: true,
                label: line,
                hint: accessibilityHint,
                child: content,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Emoji bar + right-aligned dates + optional promotion / resolution rows.
class _MessageLifecycleFooter extends StatelessWidget {
  const _MessageLifecycleFooter({
    required this.message,
    required this.participants,
    required this.linkedCoord,
    required this.viewerReactions,
    required this.tokens,
    required this.scheme,
    required this.textTheme,
    required this.l10n,
    required this.showCoordinationFooter,
    required this.linkedEventKind,
    required this.showMarkDone,
    required this.onToggleReaction,
    required this.onOpenItem,
    required this.editedSuffix,
    this.hideTimestamp = false,
  });

  final RoomMessage message;
  final List<BeaconParticipant> participants;
  final CoordinationItem? linkedCoord;
  final CoordinationItemEventKind? linkedEventKind;
  final Set<String> viewerReactions;
  final TenturaTokens tokens;
  final ColorScheme scheme;
  final TextTheme textTheme;
  final L10n l10n;
  final bool showCoordinationFooter;
  final bool showMarkDone;
  final Future<void> Function(String messageId, String emoji) onToggleReaction;
  final VoidCallback? onOpenItem;
  final String? editedSuffix;
  final bool hideTimestamp;

  static const double _avatarSize = 16;
  static const double _iconSize = 12;
  static const double _minTapHeight = 44;

  static bool _isTerminalStatus(int? status) =>
      status == CoordinationItemStatus.resolved.value ||
      status == CoordinationItemStatus.cancelled.value ||
      status == CoordinationItemStatus.superseded.value;

  @override
  Widget build(BuildContext context) {
    final reactionEntries = RoomMessageTile._sortedReactionEntries(message);
    final showReactionTimeRow =
        reactionEntries.isNotEmpty || !hideTimestamp;

    final promotionDate = message.linkedItemUpdatedAt ?? message.linkedItemCreatedAt;
    final showPromotionRow = showCoordinationFooter &&
        message.isPromotedSourceMessage &&
        linkedCoord != null &&
        promotionDate != null;
    final keepThreadMarkInsteadOfResolution = showPromotionRow &&
        linkedCoord != null &&
        RoomMessageTile.isThreadEntryKind(linkedCoord!.kind);

    Widget? resolutionRow;
    if (showCoordinationFooter &&
        message.isPromotedSourceMessage &&
        linkedCoord != null &&
        _isTerminalStatus(message.linkedItemStatus) &&
        !keepThreadMarkInsteadOfResolution) {
      final last = message.lastStatusEvent;
      final eventKind = last != null
          ? CoordinationItemEventKind.fromInt(last.eventKind)
          : null;
      final actorId = last?.actorId ?? '';
      final at = last?.at ?? message.linkedItemResolvedAt ?? message.linkedItemUpdatedAt;
      if (eventKind != null && at != null) {
        resolutionRow = _lifecycleTapRow(
          context: context,
          profile: RoomMessageTile.profileForUserId(actorId, participants) ??
              const Profile(),
          leading: coordinationCompoundEventIcon(
            kind: linkedCoord!.kind,
            eventKind: eventKind,
            isPlanStep: linkedCoord!.isPlanStep,
            tt: tokens,
            size: _iconSize,
          ),
          accent: coordinationItemEventColor(
            tokens,
            linkedCoord!.kind,
            eventKind,
          ),
          label: coordinationEventTimelineLabel(
            l10n,
            linkedCoord!.kind,
            eventKind,
            isPlanStep: linkedCoord!.isPlanStep,
          ),
          time: RoomMessageTile._formatMessageTime(at),
          onTap: onOpenItem,
        );
      }
    }

    Widget? promotionRow;
    if (showPromotionRow) {
      final kind = linkedCoord!.kind;
      final promotionAccent = RoomMessageTile.isThreadEntryKind(kind)
          ? RoomMessageTile.threadMarkAccent(tokens, kind)
          : coordinationItemEventColor(
              tokens,
              kind,
              CoordinationItemEventKind.created,
            );
      promotionRow = _lifecycleTapRow(
        context: context,
        profile: RoomMessageTile.profileForUserId(
              message.linkedItemCreatorId ?? '',
              participants,
            ) ??
            const Profile(),
        leading: coordinationCompoundEventIcon(
          kind: kind,
          eventKind: CoordinationItemEventKind.created,
          isPlanStep: linkedCoord!.isPlanStep,
          tt: tokens,
          size: _iconSize,
          accentOverride: promotionAccent,
        ),
        accent: promotionAccent,
        label: RoomMessageTile._coordKindShortLabel(l10n, kind),
        time: RoomMessageTile._formatMessageTime(promotionDate),
        onTap: onOpenItem,
      );
    }

    Widget? eventRow;
    if (showCoordinationFooter &&
        !message.isPromotedSourceMessage &&
        linkedCoord != null &&
        linkedEventKind != null) {
      final at =
          message.linkedItemUpdatedAt ??
          message.linkedItemCreatedAt ??
          message.createdAt;
      final kind = linkedCoord!.kind;
      final useThreadMarkAccent = RoomMessageTile.isThreadEntryKind(kind);
      final eventAccent = useThreadMarkAccent
          ? RoomMessageTile.threadMarkAccent(tokens, kind)
          : coordinationItemEventColor(
              tokens,
              kind,
              linkedEventKind!,
            );
      eventRow = _lifecycleTapRow(
        context: context,
        profile: RoomMessageTile.profileForUserId(
              message.authorId,
              participants,
            ) ??
            message.author,
        leading: coordinationCompoundEventIcon(
          kind: kind,
          eventKind: linkedEventKind!,
          isPlanStep: linkedCoord!.isPlanStep,
          tt: tokens,
          size: _iconSize,
          accentOverride: useThreadMarkAccent ? eventAccent : null,
        ),
        accent: eventAccent,
        label: coordinationEventTimelineLabel(
          l10n,
          kind,
          linkedEventKind!,
          isPlanStep: linkedCoord!.isPlanStep,
        ),
        time: RoomMessageTile._formatMessageTime(at),
        onTap: onOpenItem,
      );
    }

    Widget? markDoneRow;
    if (showMarkDone) {
      final actorProfile = RoomMessageTile.profileForUserId(
            message.semanticActorId ?? '',
            participants,
          ) ??
          const Profile();
      markDoneRow = Align(
        alignment: Alignment.centerRight,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TenturaAvatar.tiny(profile: actorProfile, size: _avatarSize),
            SizedBox(width: tokens.iconTextGap / 4),
            Icon(Icons.task_alt, size: _iconSize, color: tokens.good),
            SizedBox(width: tokens.iconTextGap / 4),
            Text(
              l10n.beaconRoomSemanticDone,
              style: textTheme.labelSmall?.copyWith(
                color: tokens.good,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }

    final dateLine = hideTimestamp
        ? null
        : [
            RoomMessageTile._formatMessageTime(
              message.editedAt ?? message.createdAt,
            ),
            if (editedSuffix != null) editedSuffix,
          ].join(' · ');

    if (!showReactionTimeRow &&
        promotionRow == null &&
        resolutionRow == null &&
        eventRow == null &&
        markDoneRow == null) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: EdgeInsets.only(top: tokens.rowGap / 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showReactionTimeRow)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Wrap(
                    spacing: kSpacingSmall,
                    runSpacing: kSpacingSmall / 2,
                    children: [
                      for (final entry in reactionEntries)
                        UnconstrainedBox(
                          key: ValueKey('${message.id}-re-${entry.key}'),
                          constrainedAxis: Axis.vertical,
                          alignment: Alignment.centerLeft,
                          child: InkWell(
                            onTap: () => unawaited(
                              onToggleReaction(message.id, entry.key),
                            ),
                            onLongPress:
                                (message.reactors[entry.key]?.isNotEmpty ??
                                    false)
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
                                      : scheme.surfaceContainerHighest
                                            .withValues(alpha: 0.75),
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
                                        message.reactors[entry.key] ??
                                        const [],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (dateLine != null)
                  Padding(
                    padding: EdgeInsets.only(left: tokens.iconTextGap / 2),
                    child: Text(
                      dateLine,
                      style: textTheme.labelSmall,
                    ),
                  ),
              ],
            ),
          if (promotionRow != null) ...[
            SizedBox(height: tokens.rowGap / 4),
            promotionRow,
          ],
          if (resolutionRow != null) ...[
            SizedBox(height: tokens.rowGap / 4),
            resolutionRow,
          ],
          if (eventRow != null) ...[
            SizedBox(height: tokens.rowGap / 4),
            eventRow,
          ],
          if (markDoneRow != null) ...[
            SizedBox(height: tokens.rowGap / 4),
            markDoneRow,
          ],
        ],
      ),
    );
  }

  Widget _lifecycleTapRow({
    required BuildContext context,
    required Profile profile,
    required Widget leading,
    required Color accent,
    required String label,
    required String time,
    required VoidCallback? onTap,
  }) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TenturaAvatar.tiny(profile: profile, size: _avatarSize),
        SizedBox(width: tokens.iconTextGap / 4),
        leading,
        SizedBox(width: tokens.iconTextGap / 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textTheme.labelSmall?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(width: tokens.iconTextGap / 4),
        Text(
          time,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
        if (onTap != null) ...[
          SizedBox(width: tokens.iconTextGap / 4),
          Icon(
            Icons.chevron_right,
            size: _iconSize,
            color: scheme.onSurfaceVariant,
          ),
        ],
      ],
    );

    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: _minTapHeight),
      child: Align(
        alignment: Alignment.centerRight,
        child: row,
      ),
    );

    if (onTap == null) return content;
    return Align(
      alignment: Alignment.centerRight,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(tokens.cardRadius / 2),
          child: Semantics(
            button: true,
            label: label,
            child: content,
          ),
        ),
      ),
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
                    child: TenturaAvatar.tiny(
                      profile: visible[i],
                      size: _size,
                      isSelf: SelfUserHighlight.profileIsSelf(
                        visible[i],
                        state.profile.id,
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
