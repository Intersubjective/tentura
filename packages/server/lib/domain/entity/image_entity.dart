import 'package:freezed_annotation/freezed_annotation.dart';

part 'image_entity.freezed.dart';

@freezed
abstract class ImageEntity with _$ImageEntity {
  const factory ImageEntity({
    required String id,
    required String authorId,
    @Default(0) int height,
    @Default(0) int width,
    @Default('') String blurHash,
  }) = _ImageEntity;

  const ImageEntity._();
}
