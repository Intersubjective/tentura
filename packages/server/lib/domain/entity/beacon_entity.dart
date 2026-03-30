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
    @Default(0) int state,
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

  bool get isActive => state == 0;
  bool get isClosed => state == 1;
  bool get isDeleted => state == 2;

  /// Shown under My Work "Active" (OPEN, DRAFT, PENDING_REVIEW).
  bool get isLifecycleActive => state == 0 || state == 3 || state == 4;

  /// Shown under My Work "Closed" (CLOSED, DELETED).
  bool get isLifecycleClosed => state == 1 || state == 2;

  bool get hasImage => image != null;

  String get imageUrl => hasImage
      ? '$kImageServer/$kImagesPath/${author.id}/${image!.id}.$kImageExt'
      : kBeaconPlaceholderUrl;

  Map<String, Object> get asJson => {'id': id};
}
