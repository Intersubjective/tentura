import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'involved_beacon_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class InvolvedBeaconState extends StateBase with _$InvolvedBeaconState {
  const factory InvolvedBeaconState({
    required String authorId,
    @Default([]) List<Beacon> beacons,
    @Default(false) bool hasReachedLast,
    @Default(StateIsSuccess()) StateStatus status,
    Object? loadError,
  }) = _InvolvedBeaconState;

  const InvolvedBeaconState._();

  bool get hasError => loadError != null;
}
