import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/room_message_attachment.dart';
import 'package:tentura/features/beacon_threads/ui/widget/room_attachment_widgets.dart';
import 'package:tentura/ui/l10n/l10n.dart';

/// Horizontal strip of pending uploads and/or existing fact attachments
/// (create composer + edit fact). Thumbs for images; chips for files.
class FactAttachmentPreviewStrip extends StatelessWidget {
  const FactAttachmentPreviewStrip({
    required this.existing,
    required this.pending,
    required this.onRemoveExisting,
    required this.onRemovePending,
    this.enabled = true,
    super.key,
  });

  final List<RoomMessageAttachment> existing;
  final List<({Uint8List bytes, String fileName, String mimeType})> pending;
  final ValueChanged<int> onRemoveExisting;
  final ValueChanged<int> onRemovePending;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    if (existing.isEmpty && pending.isEmpty) {
      return const SizedBox.shrink();
    }
    final tt = context.tt;
    final thumb = tt.avatarSize * 2;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < existing.length; i++) ...[
            if (i > 0) SizedBox(width: tt.tightGap * 2),
            _ExistingThumb(
              attachment: existing[i],
              size: thumb,
              enabled: enabled,
              onRemove: () => onRemoveExisting(i),
            ),
          ],
          if (existing.isNotEmpty && pending.isNotEmpty)
            SizedBox(width: tt.tightGap * 2),
          for (var i = 0; i < pending.length; i++) ...[
            if (i > 0) SizedBox(width: tt.tightGap * 2),
            _PendingThumb(
              bytes: pending[i].bytes,
              fileName: pending[i].fileName,
              mimeType: pending[i].mimeType,
              size: thumb,
              enabled: enabled,
              onRemove: () => onRemovePending(i),
            ),
          ],
        ],
      ),
    );
  }
}

class _ExistingThumb extends StatelessWidget {
  const _ExistingThumb({
    required this.attachment,
    required this.size,
    required this.enabled,
    required this.onRemove,
  });

  final RoomMessageAttachment attachment;
  final double size;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    if (attachment.isImage && attachment.imageId.isNotEmpty) {
      return _RemovableThumb(
        size: size,
        enabled: enabled,
        onRemove: onRemove,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
          child: SizedBox(
            width: size,
            height: size,
            child: roomAttachmentAlbumThumbnail(context, attachment),
          ),
        ),
      );
    }
    final name = attachment.fileName.trim().isNotEmpty
        ? attachment.fileName
        : l10n.beaconRoomAttachmentUntitled;
    return InputChip(
      label: Text(
        name,
        style: TenturaText.bodySmall(scheme.onSurface),
        overflow: TextOverflow.ellipsis,
      ),
      onDeleted: enabled ? onRemove : null,
      deleteIcon: Icon(Icons.close, size: tt.iconSize),
    );
  }
}

class _PendingThumb extends StatelessWidget {
  const _PendingThumb({
    required this.bytes,
    required this.fileName,
    required this.mimeType,
    required this.size,
    required this.enabled,
    required this.onRemove,
  });

  final Uint8List bytes;
  final String fileName;
  final String mimeType;
  final double size;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final isImage = mimeType.toLowerCase().startsWith('image/');
    if (!isImage) {
      final name = fileName.trim().isEmpty
          ? l10n.beaconRoomAttachmentUntitled
          : fileName;
      return InputChip(
        label: Text(
          name,
          style: TenturaText.bodySmall(scheme.onSurface),
          overflow: TextOverflow.ellipsis,
        ),
        onDeleted: enabled ? onRemove : null,
        deleteIcon: Icon(Icons.close, size: tt.iconSize),
      );
    }
    return _RemovableThumb(
      size: size,
      enabled: enabled,
      onRemove: onRemove,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
        child: SizedBox(
          width: size,
          height: size,
          child: Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => Icon(
              Icons.broken_image_outlined,
              color: scheme.outline,
              size: tt.iconSize,
            ),
          ),
        ),
      ),
    );
  }
}

class _RemovableThumb extends StatelessWidget {
  const _RemovableThumb({
    required this.size,
    required this.enabled,
    required this.onRemove,
    required this.child,
  });

  final double size;
  final bool enabled;
  final VoidCallback onRemove;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tt = context.tt;
    final loc = MaterialLocalizations.of(context);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        if (enabled)
          Positioned(
            top: 0,
            right: 0,
            child: Material(
              color: scheme.surface.withValues(alpha: 0.92),
              shape: const CircleBorder(),
              clipBehavior: Clip.antiAlias,
              child: IconButton(
                padding: EdgeInsets.zero,
                constraints: BoxConstraints.tightFor(
                  width: tt.buttonHeight / 2,
                  height: tt.buttonHeight / 2,
                ),
                tooltip: loc.deleteButtonTooltip,
                iconSize: tt.iconSize,
                onPressed: onRemove,
                icon: Icon(Icons.close, color: scheme.onSurface),
              ),
            ),
          ),
      ],
    );
  }
}
