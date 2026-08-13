import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/availability.dart';
import 'package:tentura_root/domain/enums.dart';

part 'user_availability_entity.freezed.dart';

@freezed
abstract class UserAvailabilityEntity with _$UserAvailabilityEntity {
  const factory UserAvailabilityEntity({
    required String userId,
    @Default(false) bool isLimited,
    DateTime? resumeOn,
  }) = _UserAvailabilityEntity;

  const UserAvailabilityEntity._();

  AvailabilityView effectiveOn(DateTime todayUtc) => availabilityViewOn(
    isLimited: isLimited,
    resumeOn: resumeOn,
    todayUtc: todayUtc,
  );

  bool blocksNewRequestsOn(DateTime todayUtc) =>
      effectiveOn(todayUtc) == AvailabilityView.paused;
}
