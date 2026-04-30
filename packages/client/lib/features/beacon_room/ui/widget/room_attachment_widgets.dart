import 'dart:async';

import 'package:blurhash_shader/blurhash_shader.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Inline PageView height for multi-image room messages and pinned facts
/// (keep in sync with layout in RoomMessageInlineImageAlbum).
const double kRoomMessageInlineImageAlbumHeight = 220;

String roomAttachmentImageUrl(RoomMessageAttachment a) =>
    '$kImageServer/$kImagesPath/${a.imageAuthorId}/${a.imageId}.$kImageExt';

/// Letterboxed thumbnail for the inline image album (BoxFit.contain, no crop).
Widget roomAttachmentAlbumThumbnail(
  BuildContext context,
  RoomMessageAttachment a,
) {
  if (a.imageId.isEmpty) {
    return const Center(child: Icon(Icons.broken_image_outlined));
  }
  final url = roomAttachmentImageUrl(a);
  final bg = Theme.of(context).colorScheme.surfaceContainerHighest;
  final img = Image.network(
    url,
    fit: BoxFit.contain,
    errorBuilder: (_, _, _) => const Center(
      child: Icon(Icons.broken_image_outlined),
    ),
  );
  return ColoredBox(
    color: bg,
    child: Center(
      child: a.blurHash.isEmpty
          ? img
          : BlurHash(a.blurHash, child: img),
    ),
  );
}

/// Human-readable attachment size label (KB / MB).
String formatRoomAttachmentSize(int bytes) {
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

/// Inline image strip (fixed height): one or more thumbnails, BoxFit.contain.
class RoomMessageInlineImageAlbum extends StatefulWidget {
  const RoomMessageInlineImageAlbum({
    required this.attachments,
    super.key,
  });

  final List<RoomMessageAttachment> attachments;

  @override
  State<RoomMessageInlineImageAlbum> createState() =>
      _RoomMessageInlineImageAlbumState();
}

class _RoomMessageInlineImageAlbumState
    extends State<RoomMessageInlineImageAlbum> {
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
              height: kRoomMessageInlineImageAlbumHeight,
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
                      openRoomAttachmentImageAlbum(context, items, index),
                    ),
                    child: roomAttachmentAlbumThumbnail(ctx, a),
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

Future<void> openRoomAttachmentImageAlbum(
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
      builder: (_) => RoomAttachmentFullscreenGallery(
        attachments: items,
        initialIndex: i,
      ),
    ),
  );
}

/// Full-screen swipe gallery for room message image attachments.
class RoomAttachmentFullscreenGallery extends StatefulWidget {
  const RoomAttachmentFullscreenGallery({
    required this.attachments,
    required this.initialIndex,
    super.key,
  });

  final List<RoomMessageAttachment> attachments;
  final int initialIndex;

  @override
  State<RoomAttachmentFullscreenGallery> createState() =>
      _RoomAttachmentFullscreenGalleryState();
}

class _RoomAttachmentFullscreenGalleryState
    extends State<RoomAttachmentFullscreenGallery> {
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
          final url = roomAttachmentImageUrl(a);
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

/// Images + files (fixed-height image album thumbnails + file chips).
class RoomPinnedStyleAttachments extends StatelessWidget {
  const RoomPinnedStyleAttachments({
    required this.attachments,
    required this.l10n,
    this.onOpenFileAttachment,
    super.key,
  });

  final List<RoomMessageAttachment> attachments;
  final L10n l10n;
  final Future<void> Function(RoomMessageAttachment attachment)?
      onOpenFileAttachment;

  @override
  Widget build(BuildContext context) {
    final imageAttachments = attachments
        .where((a) => a.isImage && a.imageId.isNotEmpty)
        .toList();
    final fileAttachments = attachments.where((a) => a.isFile).toList();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (imageAttachments.isNotEmpty)
          RoomMessageInlineImageAlbum(
            attachments: imageAttachments,
          ),
        if (fileAttachments.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(
              top: imageAttachments.isNotEmpty ? kSpacingSmall : 0,
            ),
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
                        if (formatRoomAttachmentSize(a.sizeBytes).isNotEmpty)
                          ' · ${formatRoomAttachmentSize(a.sizeBytes)}',
                      ].join(),
                    ),
                    onPressed: onOpenFileAttachment == null
                        ? null
                        : () => unawaited(onOpenFileAttachment!(a)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
