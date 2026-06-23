import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_root/domain/entity/coordinates.dart';

import 'package:tentura_server/consts.dart';
import 'package:tentura_server/utils/id.dart';

import 'image_entity.dart';
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
    @Default(0) int state,
    @Default('') String description,
    @Default([]) List<ImageEntity> images,
    Coordinates? coordinates,
    DateTime? startAt,
    DateTime? endAt,
    String? context,
    Set<String>? tags,
    @Default(<String>{}) Set<String> needs,
    String? iconCode,
    int? iconBackground,
    String? needSummary,
    String? successCriteria,
    String? lineageParentBeaconId,
    String? lineageRootBeaconId,
  }) = _BeaconEntity;

  const BeaconEntity._();

  bool get isActive => state == 0;
  bool get isCancelled => state == 1;
  bool get isDeleted => state == 2;
  bool get isWrappingUp => state == 5;
  bool get isFinished => state == 1 || state == 6;

  /// NOW + coordination edits allowed in OPEN (0) and WRAPPING UP (5).
  bool get allowsCoordination => state == 0 || state == 5;

  /// Forwarding only while OPEN.
  bool get allowsForward => state == 0;

  /// Shown under My Work "Active" (OPEN, DRAFT, WRAPPING UP).
  bool get isLifecycleActive => state == 0 || state == 3 || state == 5;

  /// Shown under My Work "Closed" (CANCELLED, DELETED, CLOSED).
  bool get isLifecycleClosed => state == 1 || state == 2 || state == 6;

  /// Withdraw (`beaconWithdraw`) allowed only for OPEN and WRAPPING UP.
  bool get allowsBeaconWithdraw => state == 0 || state == 5;

  bool get hasImage => images.isNotEmpty;

  String get imageUrl => hasImage
      ? '$kImageServer/$kImagesPath/${author.id}/${images.first.id}.$kImageExt'
      : kBeaconPlaceholderUrl;

  /// V2 GraphQL `Beacon` shape (camelCase); keep in sync with `gqlTypeBeacon` in custom_types.dart.
  Map<String, Object?> get asJson => {
    'id': id,
    'iconCode': iconCode,
    'iconBackground': iconBackground,
  };
}
