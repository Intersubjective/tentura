import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:injectable/injectable.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';

export 'package:image_picker/image_picker.dart' show XFile;

@injectable
class ImageRepository {
  final _imagePicker = ImagePicker();

  Future<ImageEntity?> pickImage() async {
    final maxDimension = kImageMaxDimension.toDouble();
    final xFile = await _imagePicker.pickImage(
      maxHeight: maxDimension,
      maxWidth: maxDimension,
      source: ImageSource.gallery,
    );
    return xFile == null ? null : _xFileToEntity(xFile);
  }

  Future<List<ImageEntity>> pickMultipleImages() async {
    final maxDimension = kImageMaxDimension.toDouble();
    final xFiles = await _imagePicker.pickMultiImage(
      maxHeight: maxDimension,
      maxWidth: maxDimension,
    );
    final results = <ImageEntity>[];
    for (final xFile in xFiles) {
      results.add(await _xFileToEntity(xFile));
    }
    return results;
  }

  Future<ImageEntity> _xFileToEntity(XFile xFile) async {
    final name = xFile.name.toLowerCase();
    final Uint8List bytes;

    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      bytes = await xFile.readAsBytes();
    } else if (name.endsWith('.png')) {
      bytes = img.encodeJpg(
        img.decodePng(await xFile.readAsBytes()) ??
            (throw const FormatException('Cant decode image')),
      );
    } else if (name.endsWith('.webp')) {
      bytes = img.encodeJpg(
        img.decodeWebP(await xFile.readAsBytes()) ??
            (throw const FormatException('Cant decode image')),
      );
    } else {
      bytes = img.encodeJpg(
        img.decodeImage(await xFile.readAsBytes()) ??
            (throw const FormatException('Cant decode image')),
      );
    }

    return ImageEntity(
      imageBytes: bytes,
      fileName: xFile.name,
    );
  }
}
