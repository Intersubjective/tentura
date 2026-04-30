import 'dart:async';
import 'dart:convert';

import 'package:blurhash_shader/blurhash_shader.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/room_message.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/profile/ui/bloc/profile_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/self_aware_profile_avatar.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

class RoomMessageTile extends StatelessWidget {
  const RoomMessageTile({
    required this.message,
    required this.myProfile,
    required this.onToggleReaction,
    this.onActionsPressed,
    this.onOpenFileAttachment,
    super.key,
  });

  final RoomMessage message;

  /// Current user (for aligning / styling mine vs others').
  final Profile myProfile;

  /// Open actions for this message (overflow menu).
  final void Function(RoomMessage message)? onActionsPressed;

  /// Member-only file attachments (download + share flow).
  final Future<void> Function(RoomMessageAttachment attachment)?
      onOpenFileAttachment;

  final Future<void> Function(String messageId, String emoji) onToggleReaction;

  static String _semanticShortLabel(int? marker) => switch (marker) {
        BeaconRoomSemanticMarker.updatePlan => 'Plan',
        BeaconRoomSemanticMarker.pinFactPublic => 'Public fact',
        BeaconRoomSemanticMarker.pinFactPrivate => 'Room fact',
        BeaconRoomSemanticMarker.participantStatusChanged => 'Status',
        BeaconRoomSemanticMarker.blocker => 'Blocker',
        BeaconRoomSemanticMarker.needInfo => 'Need info',
        BeaconRoomSemanticMarker.done => 'Done',
        _ => marker == null ? '' : 'System',
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

  static bool _viewerReactedWith(RoomMessage m, String emoji) {
    final raw = m.myReaction;
    if (raw == null || raw.isEmpty) return false;
    return raw.split(',').map((s) => s.trim()).contains(emoji);
  }

  static int _emojiCount(RoomMessage m, String emoji) =>
      m.reactionCounts[emoji] ?? 0;

  static String _formatAttachmentSize(int bytes) {
    if (bytes <= 0) {
      return '';
    }
    if (bytes < 1024) {
      return '$bytes B';
    }
    final kb = bytes / 1024;
    if (kb < 1024) {
      return '${kb.toStringAsFixed(kb >= 10 ? 0 : 1)} KB';
    }
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB';
  }

  static String _imageUrl(RoomMessageAttachment a) =>
      '$kImageServer/$kImagesPath/${a.imageAuthorId}/${a.imageId}.$kImageExt';

  static Future<void> _openImagePreview(
    BuildContext context,
    RoomMessageAttachment a,
  ) async {
    if (a.imageId.isEmpty) {
      return;
    }
    final url = _imageUrl(a);
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: kPaddingH,
        child: InteractiveViewer(
          child: AspectRatio(
            aspectRatio: a.width > 0 && a.height > 0 ? a.width / a.height : 1,
            child: a.blurHash.isEmpty
                ? Image.network(url, fit: BoxFit.contain)
                : BlurHash(
                    a.blurHash,
                    child: Image.network(url, fit: BoxFit.contain),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final theme = Theme.of(context);
    final isMine = message.authorId == myProfile.id;
    final semantic = _semanticShortLabel(message.semanticMarker);
    final display = _bodyForDisplay(message);
    final isStateCard = message.semanticMarker == BeaconRoomSemanticMarker.blocker ||
        message.semanticMarker == BeaconRoomSemanticMarker.needInfo ||
        message.semanticMarker == BeaconRoomSemanticMarker.done;

    final reacted = _viewerReactedWith(
      message,
      BeaconRoomMessageReaction.defaultEmoji,
    );
    final thumbCount =
        _emojiCount(message, BeaconRoomMessageReaction.defaultEmoji);

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
                          padding: const EdgeInsets.only(right: kSpacingMedium),
                          child: SelfAwareAvatar.small(profile: message.author),
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
                                  child: BlocBuilder<ProfileCubit, ProfileState>(
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
                                IconButton(
                                  tooltip:
                                      l10n.beaconRoomMessageActionsTitle,
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
                            if (message.attachments.isNotEmpty)
                              Padding(
                                padding: kPaddingSmallT,
                                child: Wrap(
                                  spacing: kSpacingSmall,
                                  runSpacing: kSpacingSmall,
                                  children: [
                                    for (final a in message.attachments)
                                      if (a.isImage && a.imageId.isNotEmpty)
                                        InkWell(
                                          onTap: () => unawaited(
                                            _openImagePreview(context, a),
                                          ),
                                          borderRadius:
                                              BorderRadius.circular(8),
                                          child: ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(8),
                                            child: SizedBox(
                                              width: 96,
                                              height: 96,
                                              child: a.blurHash.isEmpty
                                                  ? Image.network(
                                                      _imageUrl(a),
                                                      fit: BoxFit.cover,
                                                      errorBuilder:
                                                          (_, _, _) =>
                                                              const Center(
                                                        child: Icon(
                                                          Icons
                                                              .broken_image_outlined,
                                                        ),
                                                      ),
                                                    )
                                                  : BlurHash(
                                                      a.blurHash,
                                                      child: Image.network(
                                                        _imageUrl(a),
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (_, _, _) =>
                                                                const Center(
                                                          child: Icon(
                                                            Icons
                                                                .broken_image_outlined,
                                                          ),
                                                        ),
                                                      ),
                                                    ),
                                            ),
                                          ),
                                        )
                                      else if (a.isFile)
                                        ActionChip(
                                          avatar: const Icon(
                                            Icons.insert_drive_file_outlined,
                                            size: 22,
                                          ),
                                          label: Text(
                                            [
                                              if (a.fileName
                                                  .trim()
                                                  .isNotEmpty)
                                                a.fileName
                                              else
                                                l10n.beaconRoomAttachmentUntitled,
                                              if (_formatAttachmentSize(
                                                    a.sizeBytes,
                                                  )
                                                  .isNotEmpty)
                                                ' · ${_formatAttachmentSize(a.sizeBytes)}',
                                            ].join(),
                                          ),
                                          onPressed:
                                              onOpenFileAttachment == null
                                              ? null
                                              : () => unawaited(
                                                  onOpenFileAttachment!(a),
                                                ),
                                        ),
                                  ],
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
                      children: [
                        Text(
                          _formatTime(message.createdAt),
                          style: theme.textTheme.labelSmall,
                        ),
                        const Spacer(),
                        InkWell(
                          onTap: () => unawaited(
                            onToggleReaction(
                              message.id,
                              BeaconRoomMessageReaction.defaultEmoji,
                            ),
                          ),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: kPaddingSmallH,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  BeaconRoomMessageReaction.defaultEmoji,
                                  style:
                                      theme.textTheme.titleMedium?.copyWith(
                                    color: reacted
                                        ? theme.colorScheme.primary
                                        : null,
                                  ),
                                ),
                                if (thumbCount > 0) ...[
                                  const SizedBox(width: kSpacingSmall),
                                  Text(
                                    '$thumbCount',
                                    style: theme.textTheme.labelMedium,
                                  ),
                                ],
                              ],
                            ),
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
