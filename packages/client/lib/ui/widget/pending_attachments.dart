import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tentura_root/utils/infer_image_mime_from_bytes.dart';

import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/design_system/tentura_design_system.dart';
import 'package:tentura/domain/entity/beacon_room_consts.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/utils/ui_utils.dart' show showSnackBar;

/// Cmd+V on Apple platforms, Ctrl+V elsewhere (no Shift/Alt).
bool isPasteShortcutPressed() {
  final keyboard = HardwareKeyboard.instance;
  final isApple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  final primary = isApple ? keyboard.isMetaPressed : keyboard.isControlPressed;
  final other = isApple ? keyboard.isControlPressed : keyboard.isMetaPressed;
  return primary &&
      !other &&
      !keyboard.isShiftPressed &&
      !keyboard.isAltPressed;
}

/// Attachments picked for a message that is not sent yet: images from the
/// gallery, files, or an image pasted from the clipboard. Shared by the room
/// composer and the new-Post form, so both keep the same limits.
mixin PendingAttachmentsMixin<T extends StatefulWidget> on State<T> {
  /// In the order the user added them.
  final List<RoomPendingUpload> pendingUploads = [];

  ImageRepository get attachmentImageRepository;

  ClipboardImageRepository get attachmentClipboardRepository;

  /// Called after [pendingUploads] gained or lost an item.
  void onPendingUploadsChanged() {}

  int get remainingAttachmentSlots =>
      kMaxRoomMessageAttachments - pendingUploads.length;

  void removePendingUpload(int index) {
    setState(() => pendingUploads.removeAt(index));
    onPendingUploadsChanged();
  }

  void clearPendingUploads() {
    setState(pendingUploads.clear);
    onPendingUploadsChanged();
  }

  void _snack(String message) {
    if (!mounted) {
      return;
    }
    showSnackBar(context, text: message);
  }

  void _snackTooMany() => _snack(
    L10n.of(context)!.beaconRoomAttachmentsTooMany(kMaxRoomMessageAttachments),
  );

  bool _withinSize(List<int> bytes) {
    if (bytes.length <= kMaxRoomMessageAttachmentBytes) {
      return true;
    }
    const mb = kMaxRoomMessageAttachmentBytes ~/ (1024 * 1024);
    _snack(L10n.of(context)!.beaconRoomAttachmentTooLarge(mb));
    return false;
  }

  void _tryAdd(RoomPendingUpload upload) {
    if (remainingAttachmentSlots <= 0) {
      _snackTooMany();
      return;
    }
    if (!_withinSize(upload.bytes)) {
      return;
    }
    setState(() => pendingUploads.add(upload));
    onPendingUploadsChanged();
  }

  static String _mimeFromExtension(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'webp':
        return 'image/webp';
      case 'txt':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }

  /// file_picker 12 dropped `PlatformFile.extension`; derive from `name`.
  static String? _extensionFromFileName(String name) {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return null;
    }
    return name.substring(dot + 1).trim();
  }

  Future<void> pickImageAttachments() async {
    if (remainingAttachmentSlots <= 0) {
      _snackTooMany();
      return;
    }
    final picks = await attachmentImageRepository.pickMultipleImages();
    if (!mounted || picks.isEmpty) {
      return;
    }
    for (final p in picks) {
      if (remainingAttachmentSlots <= 0) {
        break;
      }
      _tryAdd(
        RoomPendingUpload(
          bytes: p.bytes,
          fileName: p.fileName,
          mimeType: 'image/jpeg',
        ),
      );
    }
  }

  /// Reads an image from the clipboard into the pending attachments.
  ///
  /// [fromKeyboard] is Ctrl/Cmd+V in a text field: the field pastes text in
  /// parallel, so stay silent unless the clipboard actually held an image.
  Future<void> pasteImageAttachment({bool fromKeyboard = false}) async {
    if (!fromKeyboard && remainingAttachmentSlots <= 0) {
      _snackTooMany();
      return;
    }
    final l10n = L10n.of(context)!;
    try {
      final result = await attachmentClipboardRepository.readImage();
      if (!mounted) {
        return;
      }
      switch (result.outcome) {
        case ClipboardImageReadOutcome.found:
          _tryAdd(result.upload!);
        case ClipboardImageReadOutcome.notFound:
          if (!fromKeyboard) {
            _snack(l10n.beaconRoomAttachPasteImageNotFound);
          }
        case ClipboardImageReadOutcome.unsupported:
          if (!fromKeyboard) {
            _snack(l10n.beaconRoomAttachPasteImageUnsupported);
          }
      }
    } on Object catch (_) {
      if (!mounted || fromKeyboard) {
        return;
      }
      _snack(l10n.beaconRoomAttachPasteImageReadFailed);
    }
  }

  Future<void> pickFileAttachments() async {
    if (remainingAttachmentSlots <= 0) {
      _snackTooMany();
      return;
    }
    final files = await FilePicker.pickFiles();
    if (!mounted || files.isEmpty) {
      return;
    }
    for (final pf in files) {
      if (remainingAttachmentSlots <= 0) {
        break;
      }
      final bytes = await pf.readAsBytes();
      final ext = _extensionFromFileName(pf.name);
      var mime = ext != null && ext.isNotEmpty
          ? _mimeFromExtension(ext)
          : 'application/octet-stream';
      final sniffed = inferImageMimeFromLeadingBytes(bytes);
      if (sniffed != null) {
        mime = sniffed;
      }
      _tryAdd(
        RoomPendingUpload(
          bytes: bytes,
          fileName: pf.name,
          mimeType: mime,
        ),
      );
    }
  }
}

/// One not-yet-sent attachment: an image thumbnail with a remove button, or a
/// file chip.
class PendingAttachmentPreview extends StatelessWidget {
  const PendingAttachmentPreview({
    required this.upload,
    required this.onRemove,
    this.size = 72,
    super.key,
  });

  final RoomPendingUpload upload;

  /// Null while sending: the attachment can no longer be removed.
  final VoidCallback? onRemove;

  /// Side of the square image thumbnail.
  final double size;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isImage = upload.mimeType.toLowerCase().startsWith('image/');
    if (!isImage) {
      return InputChip(
        label: Text(
          upload.fileName.trim().isEmpty
              ? L10n.of(context)!.beaconRoomAttachmentUntitled
              : upload.fileName,
          style: theme.textTheme.labelMedium,
          overflow: TextOverflow.ellipsis,
        ),
        onDeleted: onRemove,
      );
    }
    final remove = onRemove;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(TenturaRadii.cardDense),
          child: SizedBox(
            width: size,
            height: size,
            child: Image.memory(
              upload.bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Icon(
                Icons.broken_image_outlined,
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        ),
        if (remove != null)
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
              style: IconButton.styleFrom(
                backgroundColor: theme.colorScheme.surface.withValues(
                  alpha: 0.92,
                ),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              tooltip: MaterialLocalizations.of(context).deleteButtonTooltip,
              iconSize: 20,
              onPressed: remove,
              icon: Icon(Icons.close, color: theme.colorScheme.onSurface),
            ),
          ),
      ],
    );
  }
}
