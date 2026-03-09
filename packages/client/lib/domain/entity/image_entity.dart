import 'dart:typed_data';

import 'package:freezed_annotation/freezed_annotation.dart';

import 'identifiable.dart';

part 'image_entity.freezed.dart';

@freezed
abstract class ImageEntity with _$ImageEntity implements Identifiable {
  const factory ImageEntity({
    @Default('') String id,
    @Default('') String authorId,
    @Default('') String blurHash,
    @Default(0) int height,
    @Default(0) int width,
    @Default('image/jpeg') String mimeType,
    @Default('') String fileName,
    Uint8List? imageBytes,
  }) = _ImageEntity;

  const ImageEntity._();
}
