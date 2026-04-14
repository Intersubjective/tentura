import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
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

  /// Gallery pick, then native/web crop UI (1:1, circular guide on mobile).
  Future<ImageEntity?> pickAndCropImage(
    List<PlatformUiSettings> cropUiSettings,
  ) async {
    final maxDimension = kImageMaxDimension.toDouble();
    final xFile = await _imagePicker.pickImage(
      maxHeight: maxDimension,
      maxWidth: maxDimension,
      source: ImageSource.gallery,
    );
    if (xFile == null) return null;

    final croppedFile = await ImageCropper().cropImage(
      sourcePath: xFile.path,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      maxWidth: kImageMaxDimension,
      maxHeight: kImageMaxDimension,
      uiSettings: cropUiSettings,
    );
    if (croppedFile == null) return null;

    return _croppedFileToEntity(croppedFile);
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
    return _entityFromBytes(await xFile.readAsBytes(), xFile.name);
  }

  Future<ImageEntity> _croppedFileToEntity(CroppedFile croppedFile) async {
    final fileName = croppedFile.path.split(RegExp(r'[/\\]')).last;
    return _entityFromBytes(await croppedFile.readAsBytes(), fileName);
  }

  Future<ImageEntity> _entityFromBytes(
    Uint8List rawBytes,
    String fileName,
  ) async {
    final name = fileName.toLowerCase();
    final Uint8List bytes;

    if (name.endsWith('.jpg') || name.endsWith('.jpeg')) {
      bytes = rawBytes;
    } else if (name.endsWith('.png')) {
      bytes = img.encodeJpg(
        img.decodePng(rawBytes) ??
            (throw const FormatException('Cant decode image')),
      );
    } else if (name.endsWith('.webp')) {
      bytes = img.encodeJpg(
        img.decodeWebP(rawBytes) ??
            (throw const FormatException('Cant decode image')),
      );
    } else {
      bytes = img.encodeJpg(
        img.decodeImage(rawBytes) ??
            (throw const FormatException('Cant decode image')),
      );
    }

    return ImageEntity(
      imageBytes: bytes,
      fileName: fileName,
    );
  }
}
