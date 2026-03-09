import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/utils/id.dart';

import 'image_entity.dart';
import 'polling_entity.dart';
import 'user_entity.dart';

part 'beacon_entity.freezed.dart';

@freezed
abstract class BeaconEntity with _$BeaconEntity {
  static String get newId => generateId('B');

  const factory BeaconEntity({
    required String id,
    required String title,
    required UserEntity author,
    required DateTime createdAt,
    required DateTime updatedAt,
    @Default(true) bool isEnabled,
    @Default('') String description,
    Coordinates? coordinates,
    PollingEntity? polling,
    ImageEntity? image,
    DateTime? startAt,
    DateTime? endAt,
    String? context,
    Set<String>? tags,
  }) = _BeaconEntity;

  const BeaconEntity._();

  bool get hasImage => image != null;

  String get imageUrl => hasImage
      ? '$kImageServer/$kImagesPath/${author.id}/${image!.id}.$kImageExt'
      : kBeaconPlaceholderUrl;

  Map<String, Object> get asJson => {'id': id};
}
