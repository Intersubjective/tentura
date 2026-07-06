import 'dart:typed_data';

/// VM/native implementation is in [write_crop_source_io.dart]; web in
/// [write_crop_source_web.dart].
Future<String> writeCropSourceBytes(Uint8List bytes) async {
  throw UnsupportedError('writeCropSourceBytes is not available on this platform');
}

Future<void> disposeCropSourcePath(String sourcePath) async {}
