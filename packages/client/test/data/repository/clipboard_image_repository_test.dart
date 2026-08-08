import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/domain/entity/room_pending_upload.dart';

class _FakeReadProgress extends Fake implements ReadProgress {}

class _FakeDataReaderFile extends Fake implements DataReaderFile {
  _FakeDataReaderFile(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> readAll() async => bytes;
}

class _FakeClipboardReader extends Fake implements ClipboardReader {
  _FakeClipboardReader({
    required this.hasPng,
    this.pngBytes,
    this.suggestedName,
  });

  final bool hasPng;
  final Uint8List? pngBytes;
  final String? suggestedName;

  @override
  List<ClipboardDataReader> get items => const [];

  @override
  bool canProvide(DataFormat format) => hasPng && format == Formats.png;

  @override
  ReadProgress? getFile(
    FileFormat? format,
    AsyncValueChanged<DataReaderFile> onFile, {
    ValueChanged<Object>? onError,
    bool allowVirtualFiles = true,
    bool synthesizeFilesFromURIs = true,
  }) {
    if (!hasPng || format != Formats.png || pngBytes == null) {
      return null;
    }
    onFile(_FakeDataReaderFile(pngBytes!));
    return _FakeReadProgress();
  }

  @override
  Future<String?> getSuggestedName() async => suggestedName;
}

void main() {
  group('ClipboardImageRepository', () {
    test('returns populated RoomPendingUpload when image is present', () async {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final repository = ClipboardImageRepository.withReader(
        () async => _FakeClipboardReader(
          hasPng: true,
          pngBytes: bytes,
          suggestedName: 'screenshot.png',
        ),
      );

      final result = await repository.readImage();

      expect(result.outcome, ClipboardImageReadOutcome.found);
      expect(result.upload?.bytes, bytes);
      expect(result.upload?.fileName, 'screenshot.png');
      expect(result.upload?.mimeType, 'image/png');
    });

    test('uses fallback filename when clipboard source has no name', () async {
      final bytes = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47]);
      final repository = ClipboardImageRepository.withReader(
        () async => _FakeClipboardReader(
          hasPng: true,
          pngBytes: bytes,
        ),
      );

      final result = await repository.readImage();

      expect(result.upload?.fileName, 'clipboard.png');
    });

    test('returns not found when clipboard is supported but has no image', () async {
      final repository = ClipboardImageRepository.withReader(
        () async => _FakeClipboardReader(hasPng: false),
      );

      final result = await repository.readImage();

      expect(result.outcome, ClipboardImageReadOutcome.notFound);
      expect(result.upload, isNull);
    });

    test('returns unsupported when clipboard reading is unavailable', () async {
      final repository = ClipboardImageRepository.withReader(
        () async => _FakeClipboardReader(hasPng: true, pngBytes: Uint8List(1)),
        isSupported: () => false,
      );

      final result = await repository.readImage();

      expect(result.outcome, ClipboardImageReadOutcome.unsupported);
      expect(result.upload, isNull);
    });

    test('propagates read errors instead of swallowing them', () async {
      final repository = ClipboardImageRepository.withReader(
        () async => throw StateError('permission denied'),
      );

      expect(
        repository.readImage(),
        throwsA(isA<StateError>()),
      );
    });

    test('propagates getFile/readValue errors from the reader', () async {
      final repository = ClipboardImageRepository.withReader(
        () async => _ThrowingClipboardReader(),
      );

      expect(
        repository.readImage(),
        throwsA(isA<FormatException>()),
      );
    });
  });
}

class _ThrowingClipboardReader extends Fake implements ClipboardReader {
  @override
  List<ClipboardDataReader> get items => const [];

  @override
  bool canProvide(DataFormat format) => format == Formats.png;

  @override
  Future<String?> getSuggestedName() async => null;

  @override
  ReadProgress? getFile(
    FileFormat? format,
    AsyncValueChanged<DataReaderFile> onFile, {
    ValueChanged<Object>? onError,
    bool allowVirtualFiles = true,
    bool synthesizeFilesFromURIs = true,
  }) {
    onError?.call(const FormatException('read failed'));
    return null;
  }
}
