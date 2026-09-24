import 'package:freezed_annotation/freezed_annotation.dart';

part 'room_read_watermark.freezed.dart';

@freezed
abstract class RoomReadWatermark with _$RoomReadWatermark {
  const factory RoomReadWatermark({
    required String userId,
    required DateTime lastSeenAt,
    @Default('') String userTitle,
    @Default(false) bool userHasPicture,
    @Default('') String userImageId,
    @Default('') String userBlurHash,
    @Default(0) int userPicHeight,
    @Default(0) int userPicWidth,
  }) = _RoomReadWatermark;
}
