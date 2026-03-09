import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/enum.dart';

part 'beacon_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class BeaconState extends StateBase with _$BeaconState {
  const factory BeaconState({
    required String profileId,
    @Default(false) bool isMine,
    @Default([]) List<Beacon> beacons,
    @Default(false) bool hasReachedLast,
    @Default(BeaconFilter.enabled) BeaconFilter filter,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _BeaconState;

  const BeaconState._();
}
