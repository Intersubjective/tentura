import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import 'package:tentura/domain/entity/beacon_participant.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/domain/entity/room_poll_data.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_poll_card.dart';
import 'package:tentura/features/beacon_room/ui/widget/room_reaction_picker.dart';
import 'package:tentura/features/beacon_view/ui/widget/self_aware_plain_mini_avatar.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

class RoomMessageTile extends StatelessWidget {
  const RoomMessageTile({
    required this.message,
    required this.myProfile,
    required this.onToggleReaction,
    this.onPinnedFactManage,
    this.onActionsPressed,
    this.onOpenFileAttachment,
    this.onVotePoll,
    this.participants = const [],
    super.key,
  });

  final RoomMessage message;

  /// When non-null (message already has a pinned fact), filled pin beside overflow opens fact actions.
  final Future<void> Function()? onPinnedFactManage;

  /// Current user (for aligning / styling mine vs others').
  final Profile myProfile;

  /// Open actions for this message (overflow menu).
  final void Function(RoomMessage message)? onActionsPressed;

  /// Member-only file attachments (download + share flow).
  final Future<void> Function(RoomMessageAttachment attachment)?
  onOpenFileAttachment;

  final Future<void> Function(String messageId, String emoji) onToggleReaction;

  final Future<void> Function(
    String pollingId,
    List<String> variantIds, {
    int? score,
  })? onVotePoll;

  final List<BeaconParticipant> participants;

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

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final isMine = message.authorId == myProfile.id;
    final semantic = _semanticShortLabel(l10n, message.semanticMarker);
    final display = _bodyForDisplay(message);
    final isStateCard =
        message.semanticMarker == BeaconRoomSemanticMarker.blocker ||
        message.semanticMarker == BeaconRoomSemanticMarker.needInfo ||
        message.semanticMarker == BeaconRoomSemanticMarker.done;

    final viewerReactions = _viewerReactionEmojiSet(message);

    final imageAttachments = message.attachments
        .where((a) => a.isImage && a.imageId.isNotEmpty)
        .toList();
    final fileAttachments = message.attachments.where((a) => a.isFile).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Divider(),
        Material(
          color: Colors.transparent,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: isStateCard
                  ? theme.colorScheme.tertiaryContainer.withValues(
                      alpha: 0.35,
                    )
                  : null,
              borderRadius: BorderRadius.circular(12),
              border: isStateCard
                  ? Border.all(color: theme.colorScheme.tertiary)
                  : null,
            ),
            child: Padding(
              padding: kPaddingH.add(kPaddingSmallT),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      GestureDetector(
                        onTap: isMine
                            ? null
                            : () => context.read<ScreenCubit>().showProfile(
                                message.author.id,
                              ),
                        child: Padding(
                          padding: const EdgeInsets.only(right: kSpacingSmall),
                          child: SelfAwarePlainMiniAvatar(
                            profile: message.author,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child:
                                      BlocBuilder<ProfileCubit, ProfileState>(
                                        buildWhen: (p, c) =>
                                            p.profile.id != c.profile.id,
                                        builder: (context, state) {
                                          final isSelf =
                                              SelfUserHighlight.profileIsSelf(
                                                message.author,
                                                state.profile.id,
                                              );
                                          return Text(
                                            SelfUserHighlight.displayName(
                                              l10n,
                                              message.author,
                                              state.profile.id,
                                            ),
                                            style: SelfUserHighlight.nameStyle(
                                              theme,
                                              theme.textTheme.headlineMedium,
                                              isSelf,
                                            ),
                                          );
                                        },
                                      ),
                                ),
                                if (onPinnedFactManage != null)
                                  IconButton(
                                    tooltip: l10n.beaconRoomFactManageTooltip,
                                    icon: Icon(
                                      Icons.push_pin,
                                      size: 22,
                                      color: theme.colorScheme.primary,
                                    ),
                                    visualDensity: VisualDensity.compact,
                                    onPressed: () => unawaited(
                                      onPinnedFactManage!(),
                                    ),
                                  ),
                                IconButton(
                                  tooltip: l10n.beaconRoomMessageActionsTitle,
                                  icon: const Icon(Icons.more_vert),
                                  onPressed: onActionsPressed == null
                                      ? null
                                      : () => onActionsPressed!(message),
                                ),
                              ],
                            ),
                            if (semantic.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(
                                  top: kSpacingSmall / 2,
                                ),
                                child: Text(
                                  semantic,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.tertiary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (display.isNotEmpty)
                              Padding(
                                padding: kPaddingSmallT,
                                child: ShowMoreText(
                                  display,
                                  style: ShowMoreText.buildTextStyle(context),
                                  colorClickableText: theme.colorScheme.primary,
                                ),
                              ),
                            if (imageAttachments.isNotEmpty)
                              Padding(
                                padding: kPaddingSmallT,
                                child: RoomMessageInlineImageAlbum(
                                  attachments: imageAttachments,
                                ),
                              ),
                            if (fileAttachments.isNotEmpty)
                              Padding(
                                padding: kPaddingSmallT,
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
                                            if (_formatAttachmentSize(
                                              a.sizeBytes,
                                            ).isNotEmpty)
                                              ' · ${_formatAttachmentSize(a.sizeBytes)}',
                                          ].join(),
                                        ),
                                        onPressed: onOpenFileAttachment == null
                                            ? null
                                            : () => unawaited(
                                                onOpenFileAttachment!(a),
                                              ),
                                      ),
                                  ],
                                ),
                              ),
                            if (message.linkedPollingId != null)
                              Padding(
                                padding: kPaddingSmallT,
                                child: RoomPollCard(
                                  poll: RoomPollData.tryParse(
                                        message.pollDataJson,
                                      ) ??
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
                                      : (variantIds, {int? score}) => unawaited(
                                            onVotePoll!(
                                              message.linkedPollingId!,
                                              variantIds,
                                              score: score,
                                            ),
                                          ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  Padding(
                    padding: kPaddingSmallV,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Wrap(
                              spacing: kSpacingSmall,
                              runSpacing: kSpacingSmall / 2,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                for (final entry in _sortedReactionEntries(
                                  message,
                                ))
                                  InkWell(
                                    key: ValueKey(
                                      '${message.id}-re-${entry.key}',
                                    ),
                                    onTap: () => unawaited(
                                      onToggleReaction(
                                        message.id,
                                        entry.key,
                                      ),
                                    ),
                                    borderRadius: BorderRadius.circular(18),
                                    child: Padding(
                                      padding: kPaddingSmallH.add(
                                        const EdgeInsets.symmetric(
                                          vertical: 6,
                                        ),
                                      ),
                                      child: DecoratedBox(
                                        decoration: BoxDecoration(
                                          color:
                                              viewerReactions.contains(
                                                entry.key,
                                              )
                                              ? theme
                                                    .colorScheme
                                                    .primaryContainer
                                              : theme
                                                    .colorScheme
                                                    .surfaceContainerHighest
                                                    .withValues(alpha: 0.75),
                                          borderRadius: BorderRadius.circular(
                                            16,
                                          ),
                                          border:
                                              viewerReactions.contains(
                                                entry.key,
                                              )
                                              ? Border.all(
                                                  color:
                                                      theme.colorScheme.primary,
                                                )
                                              : null,
                                        ),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: kSpacingSmall,
                                            vertical: 2,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                entry.key,
                                                style:
                                                    theme.textTheme.titleMedium,
                                              ),
                                              const SizedBox(
                                                width: kSpacingSmall / 2,
                                              ),
                                              Text(
                                                '${entry.value}',
                                                style:
                                                    theme.textTheme.labelMedium,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                Builder(
                                  builder: (anchorCtx) {
                                    return IconButton(
                                      padding: EdgeInsets.zero,
                                      visualDensity: VisualDensity.compact,
                                      constraints: const BoxConstraints(
                                        minWidth: 44,
                                        minHeight: 44,
                                      ),
                                      iconSize: 22,
                                      tooltip:
                                          l10n.beaconRoomReactionAddTooltip,
                                      icon: Icon(
                                        Icons.add_reaction_outlined,
                                        color:
                                            theme.colorScheme.onSurfaceVariant,
                                      ),
                                      onPressed: () => unawaited(
                                        showRoomReactionPicker(
                                          anchorContext: anchorCtx,
                                          selected: viewerReactions,
                                          semanticLabel: l10n
                                              .beaconRoomReactionPickerSemantic,
                                          onPick: (emoji) => unawaited(
                                            onToggleReaction(
                                              message.id,
                                              emoji,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(
                            left: kSpacingSmall,
                            top: 2,
                          ),
                          child: Text(
                            [
                              _formatTime(message.createdAt),
                              if (message.editedAt != null)
                                l10n.beaconRoomMessageEdited,
                            ].join(' · '),
                            style: theme.textTheme.labelSmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  static String _formatTime(DateTime t) {
    final l = t.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:'
        '${l.minute.toString().padLeft(2, '0')}';
  }
}
