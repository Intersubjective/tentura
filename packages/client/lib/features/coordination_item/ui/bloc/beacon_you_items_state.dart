
import 'package:tentura/domain/entity/coordination_item.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'beacon_you_items_state.freezed.dart';

@freezed
abstract class BeaconYouItemsState extends StateBase with _$BeaconYouItemsState {
  const factory BeaconYouItemsState({
    @Default([]) List<CoordinationItem> items,
    @Default(StateIsLoading()) StateStatus status,
  }) = _BeaconYouItemsState;

  const BeaconYouItemsState._();
}
