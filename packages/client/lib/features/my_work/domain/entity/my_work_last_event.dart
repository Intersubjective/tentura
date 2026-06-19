import 'package:freezed_annotation/freezed_annotation.dart';

import 'package:tentura/domain/entity/beacon_activity_event.dart';
import 'package:tentura/domain/entity/profile.dart';

part 'my_work_last_event.freezed.dart';

@freezed
abstract class MyWorkLastEvent with _$MyWorkLastEvent {
  const factory MyWorkLastEvent({
    required BeaconActivityEvent event,
    required Profile actor,
  }) = _MyWorkLastEvent;
}
