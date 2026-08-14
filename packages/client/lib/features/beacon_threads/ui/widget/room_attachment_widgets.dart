import 'dart:async';

import 'package:blurhash_shader/blurhash_shader.dart';
import 'package:flutter/material.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';

import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart';

/// Default inline album height for [WindowClass.regular] (layout estimates).
const double kRoomMessageInlineImageAlbumHeight = 220;

/// Inline PageView height for multi-image room messages, keyed to window class.
double roomMessageInlineImageAlbumHeight(BuildContext context) =>
    switch (context.windowClass) {
      WindowClass.compact => 180,
      WindowClass.regular => 220,
      WindowClass.expanded => 280,
    };

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
    final scheme = theme.colorScheme;
    final items = widget.attachments;
    final albumHeight = roomMessageInlineImageAlbumHeight(context);

    return Semantics(
      label: 'Image gallery',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              height: albumHeight,
              width: double.infinity,
              child: items.length == 1
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => unawaited(
                        openRoomAttachmentImageAlbum(context, items, 0),
                      ),
                      child: roomAttachmentAlbumThumbnail(context, items.first),
                    )
                  : Stack(
                      alignment: Alignment.center,
                      children: [
                        PageView.builder(
                          controller: _pageController,
                          itemCount: items.length,
                          onPageChanged: (i) => setState(() => _currentPage = i),
                          itemBuilder: (ctx, index) {
                            final a = items[index];
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () => unawaited(
                                openRoomAttachmentImageAlbum(
                                  context,
                                  items,
                                  index,
                                ),
                              ),
                              child: roomAttachmentAlbumThumbnail(ctx, a),
                            );
                          },
                        ),
                        Positioned(
                          left: 0,
                          top: 0,
                          bottom: 0,
                          child: _RoomInlineImageNavButton(
                            icon: Icons.chevron_left,
                            tooltip: MaterialLocalizations.of(context)
                                .previousPageTooltip,
                            enabled: _currentPage > 0,
                            onPressed: () => _goTo(_currentPage - 1),
                            scheme: scheme,
                          ),
                        ),
                        Positioned(
                          right: 0,
                          top: 0,
                          bottom: 0,
                          child: _RoomInlineImageNavButton(
                            icon: Icons.chevron_right,
                            tooltip:
                                MaterialLocalizations.of(context).nextPageTooltip,
                            enabled: _currentPage < items.length - 1,
                            onPressed: () => _goTo(_currentPage + 1),
                            scheme: scheme,
                          ),
                        ),
                      ],
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

class _RoomInlineImageNavButton extends StatelessWidget {
  const _RoomInlineImageNavButton({
    required this.icon,
    required this.tooltip,
    required this.enabled,
    required this.onPressed,
    required this.scheme,
  });

  final IconData icon;
  final String tooltip;
  final bool enabled;
  final VoidCallback onPressed;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.88),
        elevation: 0,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: IconButton(
          tooltip: tooltip,
          icon: Icon(icon, size: 22),
          color: enabled ? scheme.onSurfaceVariant : scheme.outlineVariant,
          onPressed: enabled ? onPressed : null,
          visualDensity: VisualDensity.compact,
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
        ),
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

  void _goTo(int index) {
    unawaited(
      _controller.animateToPage(
        index,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOut,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.attachments;
    final tt = context.tt;
    final chromeBg = tt.text;
    final chromeFg = tt.surface;
    final chromeMuted = tt.textFaint;
    final materialL10n = MaterialLocalizations.of(context);
    return Scaffold(
      backgroundColor: chromeBg,
      appBar: AppBar(
        backgroundColor: chromeBg,
        foregroundColor: chromeFg,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: materialL10n.closeButtonTooltip,
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: items.length > 1
            ? Text(
                '${_index + 1} / ${items.length}',
                style: TenturaText.body(chromeFg),
              )
            : null,
      ),
      body: Stack(
        alignment: Alignment.center,
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (i) => setState(() => _index = i),
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final a = items[i];
              final url = roomAttachmentImageUrl(a);
              final img = Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Icon(
                  Icons.broken_image_outlined,
                  color: chromeMuted,
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
          if (items.length > 1) ...[
            Positioned(
              left: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: Icon(
                    Icons.chevron_left,
                    color: chromeMuted,
                    size: 40,
                  ),
                  tooltip: materialL10n.previousPageTooltip,
                  onPressed: _index > 0 ? () => _goTo(_index - 1) : null,
                ),
              ),
            ),
            Positioned(
              right: 0,
              top: 0,
              bottom: 0,
              child: Center(
                child: IconButton(
                  icon: Icon(
                    Icons.chevron_right,
                    color: chromeMuted,
                    size: 40,
                  ),
                  tooltip: materialL10n.nextPageTooltip,
                  onPressed:
                      _index < items.length - 1 ? () => _goTo(_index + 1) : null,
                ),
              ),
            ),
          ],
        ],
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
