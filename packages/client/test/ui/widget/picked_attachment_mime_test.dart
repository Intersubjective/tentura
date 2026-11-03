import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:tentura/data/repository/clipboard_image_repository.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/ui/l10n/l10n.dart';
import 'package:tentura/ui/widget/pending_attachments.dart';

import '../../support/phone_surface.dart';

const _expected = {
  'pdf': 'application/pdf',
  'txt': 'text/plain',
  'png': 'image/png',
  'jpg': 'image/jpeg',
  'jpeg': 'image/jpeg',
  'webp': 'image/webp',
  'gif': 'image/jpeg',
  'heic': 'image/jpeg',
  'heif': 'image/jpeg',
  'unknown': 'application/octet-stream',
  '': 'application/octet-stream',
};

void main() {
  testWidgets(
    'picked files retain extension MIME types and use the binary fallback for unknown names',
    (tester) async {
      await usePhoneSurface(tester);
      final platform = _Picker();
      final previous = FilePickerPlatform.instance;
      FilePickerPlatform.instance = platform;
      addTearDown(() => FilePickerPlatform.instance = previous);
      final key = GlobalKey<_ComposerState>();
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ru'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: _Composer(key: key),
        ),
      );
      final actual = <String, String>{};
      final expected = <String, String>{};
      for (final entry in _expected.entries) {
        for (final suffix in {entry.key, entry.key.toUpperCase()}) {
          final name = suffix.isEmpty ? 'file' : 'file.$suffix';
          platform.file = _PickedFile(name);
          key.currentState!.clearPendingUploads();
          await key.currentState!.pickFileAttachments().timeout(
            const Duration(seconds: 5),
          );
          await tester.pump();
          final uploads = key.currentState!.pendingUploads;
          expect(uploads, hasLength(1), reason: name);
          expect(uploads.single.fileName, name);
          expect(uploads.single.bytes, orderedEquals([1, 2, 3]));
          actual[name] = uploads.single.mimeType;
          expected[name] = entry.value;
          expect(tester.takeException(), isNull, reason: name);
          // The real preview is mounted for each selected file. Short file copy
          // keeps this MIME test independent of unrelated filename overflow.
          expect(find.byType(PendingAttachmentPreview), findsOneWidget);
        }
      }
      expect(platform.calls, expected.length);
      expect(actual, expected);
    },
  );
}

class _Picker extends FilePickerPlatform {
  late PlatformFile file;
  int calls = 0;

  @override
  Future<List<PlatformFile>> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    void Function(FilePickerStatus)? onFileLoading,
    int compressionQuality = 0,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    calls++;
    return [file];
  }
}

final class _PickedFile extends PlatformFile {
  _PickedFile(this.name);
  @override
  final String name;
  @override
  Uri get uri => Uri.dataFromBytes([1, 2, 3]);
  @override
  XFile get xFile => XFile.fromData(Uint8List.fromList([1, 2, 3]), name: name);
  @override
  Future<int> length() async => 3;
  @override
  Future<Uint8List> readAsBytes() async => Uint8List.fromList([1, 2, 3]);
  @override
  Stream<Uint8List> readAsByteStream() =>
      Stream.value(Uint8List.fromList([1, 2, 3]));
}

class _Images extends Fake implements ImageRepository {}

class _Clipboard extends Fake implements ClipboardImageRepository {}

class _Composer extends StatefulWidget {
  const _Composer({super.key});
  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer>
    with PendingAttachmentsMixin<_Composer> {
  @override
  ImageRepository get attachmentImageRepository => _Images();
  @override
  ClipboardImageRepository get attachmentClipboardRepository => _Clipboard();
  @override
  Widget build(BuildContext context) => Scaffold(
    body: ListView(
      children: [
        for (final upload in pendingUploads)
          PendingAttachmentPreview(
            upload: upload,
            onRemove: () => removePendingUpload(0),
          ),
      ],
    ),
  );
}
