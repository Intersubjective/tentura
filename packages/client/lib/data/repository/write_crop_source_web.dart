import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> writeCropSourceBytes(Uint8List bytes) async {
  final blobParts = [bytes.toJS].toJS;
  final blob = web.Blob(blobParts);
  return web.URL.createObjectURL(blob);
}

Future<void> disposeCropSourcePath(String sourcePath) async {
  if (sourcePath.startsWith('blob:')) {
    web.URL.revokeObjectURL(sourcePath);
  }
}
