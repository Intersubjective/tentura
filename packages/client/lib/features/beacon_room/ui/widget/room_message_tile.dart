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
import 'package:tentura/features/beacon_view/ui/widget/self_aware_plain_mini_avatar.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';
import 'package:tentura/ui/widget/self_user_highlight.dart';
import 'package:tentura/ui/widget/show_more_text.dart';

String _roomAttachmentImageUrl(RoomMessageAttachment a) =>
    '$kImageServer/$kImagesPath/${a.imageAuthorId}/${a.imageId}.$kImageExt';

Widget _roomAttachmentCoverImage(RoomMessageAttachment a) {
  final url = _roomAttachmentImageUrl(a);
  final net = Image.network(
    url,
    fit: BoxFit.cover,
    width: double.infinity,
    height: double.infinity,
    errorBuilder: (_, _, _) => const Center(
      child: Icon(Icons.broken_image_outlined),
    ),
  );
  return a.blurHash.isEmpty ? net : BlurHash(a.blurHash, child: net);
}

Future<void> _openRoomAttachmentImageAlbum(
  BuildContext context,
  List<RoomMessageAttachment> items,
  int initialIndex,
) async {
  if (items.isEmpty) {
    return;
  }
  final i = initialIndex.clamp(0, items.length - 1);
  await Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => _RoomAttachmentFullscreenGallery(
        attachments: items,
        initialIndex: i,
      ),
    ),
  );
}

class RoomMessageTile extends StatelessWidget {
  const RoomMessageTile({
    required this.message,
    required this.myProfile,
    required this.onToggleReaction,
    this.onPinnedFactManage,
    this.onActionsPressed,
    this.onOpenFileAttachment,
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

  String _semanticShortLabel(L10n l10n, int? marker) => switch (marker) {
        BeaconRoomSemanticMarker.updatePlan => l10n.beaconRoomSemanticPlan,
        BeaconRoomSemanticMarker.pinFactPublic => l10n.beaconRoomSemanticPublicFact,
        BeaconRoomSemanticMarker.pinFactPrivate => l10n.beaconRoomSemanticRoomFact,
        BeaconRoomSemanticMarker.participantStatusChanged =>
          l10n.beaconRoomSemanticParticipantStatus,
        BeaconRoomSemanticMarker.blocker => l10n.beaconRoomSemanticBlocker,
        BeaconRoomSemanticMarker.needInfo => l10n.beaconRoomSemanticNeedInfo,
        BeaconRoomSemanticMarker.done => l10n.beaconRoomSemanticDone,
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
      _roomAttachmentImageUrl(a);

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
    final semantic = _semanticShortLabel(l10n, message.semanticMarker);
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
                          padding: const EdgeInsets.only(right: kSpacingMedium),
                          child: SelfAwarePlainMiniAvatar(profile: message.author),
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
                            if (imageAttachments.isNotEmpty)
                              Padding(
                                padding: kPaddingSmallT,
                                child: imageAttachments.length == 1
                                    ? InkWell(
                                        onTap: () => unawaited(
                                          _openImagePreview(
                                            context,
                                            imageAttachments.single,
                                          ),
                                        ),
                                        borderRadius:
                                            BorderRadius.circular(12),
                                        child: ClipRRect(
                                          borderRadius:
                                              BorderRadius.circular(12),
                                          child: AspectRatio(
                                            aspectRatio: imageAttachments
                                                        .single.width >
                                                    0 &&
                                                imageAttachments
                                                        .single.height >
                                                    0
                                                ? imageAttachments
                                                      .single.width /
                                                    imageAttachments
                                                        .single.height
                                                : 4 / 3,
                                            child: _roomAttachmentCoverImage(
                                              imageAttachments.single,
                                            ),
                                          ),
                                        ),
                                      )
                                    : _RoomMessageImageAlbum(
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
                                            if (a.fileName
                                                .trim()
                                                .isNotEmpty)
                                              a.fileName
                                            else
                                              l10n
                                                  .beaconRoomAttachmentUntitled,
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

class _RoomMessageImageAlbum extends StatefulWidget {
  const _RoomMessageImageAlbum({required this.attachments});

  final List<RoomMessageAttachment> attachments;

  @override
  State<_RoomMessageImageAlbum> createState() => _RoomMessageImageAlbumState();
}

class _RoomMessageImageAlbumState extends State<_RoomMessageImageAlbum> {
  late final PageController _pageController;
  var _currentPage = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goTo(int index) {
    unawaited(
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = widget.attachments;

    return Semantics(
      label: 'Image gallery',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: 220,
              width: double.infinity,
              child: PageView.builder(
                controller: _pageController,
                itemCount: items.length,
                onPageChanged: (i) => setState(() => _currentPage = i),
                itemBuilder: (ctx, index) {
                  final a = items[index];
                  return GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => unawaited(
                      _openRoomAttachmentImageAlbum(context, items, index),
                    ),
                    child: _roomAttachmentCoverImage(a),
                  );
                },
              ),
            ),
          ),
          if (items.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: kSpacingSmall),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '${_currentPage + 1}/${items.length}',
                    style: theme.textTheme.labelSmall,
                  ),
                  const SizedBox(width: kSpacingSmall),
                  ...List.generate(
                    items.length,
                    (index) => Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 8,
                      ),
                      child: GestureDetector(
                        onTap: () => _goTo(index),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          width: _currentPage == index ? 10 : 7,
                          height: _currentPage == index ? 10 : 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _currentPage == index
                                ? theme.colorScheme.primary
                                : theme.colorScheme.outlineVariant,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _RoomAttachmentFullscreenGallery extends StatefulWidget {
  const _RoomAttachmentFullscreenGallery({
    required this.attachments,
    required this.initialIndex,
  });

  final List<RoomMessageAttachment> attachments;
  final int initialIndex;

  @override
  State<_RoomAttachmentFullscreenGallery> createState() =>
      _RoomAttachmentFullscreenGalleryState();
}

class _RoomAttachmentFullscreenGalleryState
    extends State<_RoomAttachmentFullscreenGallery> {
  late final PageController _controller;
  late int _index;

  @override
  void initState() {
    super.initState();
    final last = widget.attachments.length - 1;
    final clamped = widget.initialIndex.clamp(0, last < 0 ? 0 : last);
    _index = clamped;
    _controller = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.attachments;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: items.length > 1
            ? Text(
                '${_index + 1} / ${items.length}',
                style: const TextStyle(color: Colors.white),
              )
            : null,
      ),
      body: PageView.builder(
        controller: _controller,
        onPageChanged: (i) => setState(() => _index = i),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final a = items[i];
          final url = _roomAttachmentImageUrl(a);
          final img = Image.network(
            url,
            fit: BoxFit.contain,
            errorBuilder: (_, _, _) => const Icon(
              Icons.broken_image_outlined,
              color: Colors.white54,
              size: 64,
            ),
          );
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4,
            child: Center(
              child:
                  a.blurHash.isEmpty ? img : BlurHash(a.blurHash, child: img),
            ),
          );
        },
      ),
    );
  }
}
