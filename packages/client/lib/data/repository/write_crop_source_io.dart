import 'dart:io';
import 'dart:typed_data';

Future<String> writeCropSourceBytes(Uint8List bytes) async {
  final file = File(
    '${Directory.systemTemp.path}/avatar_crop_src_'
    '${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await file.writeAsBytes(bytes);
  return file.path;
}

Future<void> disposeCropSourcePath(String sourcePath) async {
  final file = File(sourcePath);
  if (file.existsSync()) {
    file.deleteSync();
  }
}
