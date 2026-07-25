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

    /// Client-generated identity for a locally picked image with no server id.
    @Default('') String localKey,
  }) = _ImageEntity;

  const ImageEntity._();

  /// Stable identity across staging: server id when known, else [localKey].
  String get key => id.isNotEmpty ? id : localKey;
}
