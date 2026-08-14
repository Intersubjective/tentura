import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/util/availability_presets.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/person_forward_row.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'person_forward_state.freezed.dart';

@freezed
abstract class PersonForwardState extends StateBase with _$PersonForwardState {
  const factory PersonForwardState({
    @Default('') String personId,
    Profile? person,
    @Default([]) List<PersonForwardRow> rows,
    String? selectedBeaconId,
    @Default('') String note,
    @Default(StateIsLoading()) StateStatus status,
    Object? loadError,
  }) = _PersonForwardState;

  const PersonForwardState._();

  PersonForwardRow? get selectedRow => selectedBeaconId == null
      ? null
      : rows.where((r) => r.beacon.id == selectedBeaconId).firstOrNull;

  bool canSendOn(DateTime todayUtc) =>
      person?.isMutuallyVisible == true &&
      (selectedRow?.isEligible ?? false) &&
      !(person?.availability.blocksNewRequestsOn(todayUtc) ?? false);

  bool get canSend => canSendOn(availabilityTodayUtc());
}
