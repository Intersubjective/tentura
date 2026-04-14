import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_cropper/image_cropper.dart';
import 'package:injectable/injectable.dart';
import 'package:image_picker/image_picker.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';

import 'read_blob_url_stub.dart'
    if (dart.library.js_interop) 'read_blob_url_web.dart';

export 'package:image_picker/image_picker.dart' show XFile;

/// Output name for cropped avatar bytes (always JPEG from ImageCropper).
const _kCroppedAvatarFileName = 'avatar_crop.jpg';

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
  ///
  /// Picker does not downscale first: the cropper must see full pixels so the
  /// exported region matches the user's crop. Output is capped via
  /// [ImageCropper] `maxWidth` / `maxHeight`.
  Future<ImageEntity?> pickAndCropImage(
    List<PlatformUiSettings> cropUiSettings,
  ) async {
    final xFile = await _imagePicker.pickImage(
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
    final path = croppedFile.path;
    final Uint8List raw;
    // Web: CroppedFile uses http.readBytes(blob:) which can return wrong data;
    // read the canvas blob with fetch instead (read_blob_url_web.dart).
    if (path.startsWith('blob:')) {
      raw = await readBlobUrlBytes(path);
    } else {
      raw = await croppedFile.readAsBytes();
    }
    return _entityFromBytes(raw, _kCroppedAvatarFileName);
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
