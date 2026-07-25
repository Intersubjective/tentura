import 'dart:typed_data';

import 'package:tentura/domain/entity/image_picked.dart';

/// Image acquisition a request editor needs, in domain terms only.
abstract interface class BeaconImagePort {
  Future<List<ImagePicked>> pickMultipleImages();

  Future<Uint8List> fetchImageBytes(String url);
}

/// Platform crop chrome, supplied by the presentation layer per call because
/// the web cropper needs a live element host.
abstract interface class ImageCropUiPort {
  /// Runs the 1:1 crop UI over [bytes]; null means the user cancelled.
  Future<ImagePicked?> cropSquare(Uint8List bytes);
}
