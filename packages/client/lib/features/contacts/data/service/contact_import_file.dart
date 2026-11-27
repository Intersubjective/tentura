import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_picked.dart';

import 'contact_file_parser.dart';

Future<List<ImportedContact>?> pickContactFile() async {
  final files = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['vcf', 'csv'],
  );
  final file = files.singleOrNull;
  if (file == null) return null;
  final bytes = await file.readAsBytes();
  final extension = file.name.split('.').last.toLowerCase();
  return switch (extension) {
    'vcf' => parseVCard(bytes),
    'csv' => parseGoogleContactsCsv(bytes),
    _ => throw const FormatException('Unsupported contact file'),
  };
}

ImagePicked? prepareContactAvatar(Uint8List bytes) {
  final photo = img.decodeImage(bytes);
  if (photo == null) return null;
  final resized = photo.width > kImageMaxDimension
      ? img.copyResize(photo, width: kImageMaxDimension)
      : photo;
  final bounded = resized.height > kImageMaxDimension
      ? img.copyResize(resized, height: kImageMaxDimension)
      : resized;
  return ImagePicked(bytes: img.encodeJpg(bounded), fileName: 'contact.jpg');
}
