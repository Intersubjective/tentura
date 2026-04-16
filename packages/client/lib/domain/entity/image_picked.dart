import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'image_entity.dart';

part 'image_picked.freezed.dart';

@freezed
abstract class ImagePicked with _$ImagePicked {
  const factory ImagePicked({
    required Uint8List bytes,
    required String fileName,
  }) = _ImagePicked;

  const ImagePicked._();

  ImageEntity toImageEntity() => ImageEntity(
    imageBytes: bytes,
    fileName: fileName,
  );
}
