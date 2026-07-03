import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura_root/domain/entity/beacon_status.dart';
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
    @Default(BeaconStatus.open) BeaconStatus status,
    DateTime? statusChangedAt,
    @Default('') String description,
    @Default([]) List<ImageEntity> images,
    Coordinates? coordinates,
    String? addressLabel,
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

  bool get isActive => status == BeaconStatus.open;

  bool get isCancelled => status == BeaconStatus.cancelled;

  bool get isDeleted => status == BeaconStatus.deleted;

  bool get isWrappingUp => status == BeaconStatus.reviewOpen;

  bool get isFinished => status.isFinished;

  bool get allowsCoordination => status.allowsCoordination;

  bool get allowsForward => status.allowsForward;

  bool get isLifecycleActive => status.isActiveSection;

  bool get isLifecycleClosed =>
      status == BeaconStatus.cancelled ||
      status == BeaconStatus.deleted ||
      status == BeaconStatus.closed;

  bool get allowsBeaconWithdraw => status.allowsCoordination;

  bool get hasImage => images.isNotEmpty;

  String get imageUrl => hasImage
      ? '$kImageServer/$kImagesPath/${author.id}/${images.first.id}.$kImageExt'
      : kBeaconPlaceholderUrl;

  /// V2 GraphQL `Beacon` shape (camelCase); keep in sync with `gqlTypeBeacon` in custom_types.dart.
  Map<String, Object?> get asJson => {
    'id': id,
    'iconCode': iconCode,
    'iconBackground': iconBackground,
    'addressLabel': addressLabel,
  };
}
