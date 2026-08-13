import 'package:freezed_annotation/freezed_annotation.dart';
import 'package:tentura_root/domain/availability.dart';
import 'package:tentura_root/domain/enums.dart';

part 'availability.freezed.dart';

@freezed
abstract class Availability with _$Availability {
  const factory Availability({
    @Default(false) bool isLimited,
    DateTime? resumeOn,
  }) = _Availability;

  const Availability._();

  factory Availability.open() => const Availability();

  AvailabilityView effectiveOn(DateTime todayUtc) => availabilityViewOn(
    isLimited: isLimited,
    resumeOn: resumeOn,
    todayUtc: todayUtc,
  );

  bool blocksNewRequestsOn(DateTime todayUtc) =>
      effectiveOn(todayUtc) == AvailabilityView.paused;
}
