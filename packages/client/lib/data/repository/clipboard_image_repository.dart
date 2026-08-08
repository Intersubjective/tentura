import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:injectable/injectable.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'package:tentura/domain/entity/room_pending_upload.dart';

import 'clipboard_support_stub.dart'
    if (dart.library.js_interop) 'clipboard_support_web.dart';

typedef ClipboardReaderProvider = Future<ClipboardReader> Function();

enum ClipboardImageReadOutcome {
  found,
  notFound,
  unsupported,
}

final class ClipboardImageReadResult {
  const ClipboardImageReadResult._({
    required this.outcome,
    this.upload,
  });

  const ClipboardImageReadResult.found(RoomPendingUpload upload)
      : this._(outcome: ClipboardImageReadOutcome.found, upload: upload);

  const ClipboardImageReadResult.notFound()
      : this._(outcome: ClipboardImageReadOutcome.notFound);

  const ClipboardImageReadResult.unsupported()
      : this._(outcome: ClipboardImageReadOutcome.unsupported);

  final ClipboardImageReadOutcome outcome;
  final RoomPendingUpload? upload;
}

class _ClipboardImageFormat {
  const _ClipboardImageFormat({
    required this.format,
    required this.mimeType,
    required this.fallbackFileName,
  });

  final DataFormat<Uint8List> format;
  final String mimeType;
  final String fallbackFileName;
}

const _kImageFormats = [
  _ClipboardImageFormat(
    format: Formats.png,
    mimeType: 'image/png',
    fallbackFileName: 'clipboard.png',
  ),
  _ClipboardImageFormat(
    format: Formats.jpeg,
    mimeType: 'image/jpeg',
    fallbackFileName: 'clipboard.jpg',
  ),
  _ClipboardImageFormat(
    format: Formats.webp,
    mimeType: 'image/webp',
    fallbackFileName: 'clipboard.webp',
  ),
  _ClipboardImageFormat(
    format: Formats.gif,
    mimeType: 'image/gif',
    fallbackFileName: 'clipboard.gif',
  ),
];

@Singleton(env: [Environment.dev, Environment.prod])
class ClipboardImageRepository {
  ClipboardImageRepository()
      : _readClipboard = ClipboardReader.readClipboard,
        _isSupported = isClipboardReadSupported;

  @visibleForTesting
  ClipboardImageRepository.withReader(
    ClipboardReaderProvider readClipboard, {
    bool Function()? isSupported,
  })  : _readClipboard = readClipboard,
        _isSupported = isSupported ?? isClipboardReadSupported;

  final ClipboardReaderProvider _readClipboard;
  final bool Function() _isSupported;

  Future<ClipboardImageReadResult> readImage() async {
    if (!_isSupported()) {
      return const ClipboardImageReadResult.unsupported();
    }

    final reader = await _readClipboard();

    for (final imageFormat in _kImageFormats) {
      if (!reader.hasValue(imageFormat.format)) {
        continue;
      }
      final bytes = await reader.readValue<Uint8List>(imageFormat.format);
      if (bytes == null || bytes.isEmpty) {
        continue;
      }
      final suggestedName = await reader.getSuggestedName();
      final fileName = _resolveFileName(
        suggestedName,
        imageFormat.fallbackFileName,
      );
      return ClipboardImageReadResult.found(
        RoomPendingUpload(
          bytes: bytes,
          fileName: fileName,
          mimeType: imageFormat.mimeType,
        ),
      );
    }

    return const ClipboardImageReadResult.notFound();
  }

  String _resolveFileName(String? suggestedName, String fallbackFileName) {
    final trimmed = suggestedName?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return fallbackFileName;
    }
    return trimmed;
  }
}
