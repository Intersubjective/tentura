import 'package:tentura/ui/bloc/state_base.dart';

part 'home_tab_reselect_state.freezed.dart';

@freezed
abstract class HomeTabReselectState extends StateBase with _$HomeTabReselectState {
  const factory HomeTabReselectState({
    @Default(StateIsSuccess()) StateStatus status,
    @Default(0) int inboxReselectCount,
    @Default(0) int myWorkReselectCount,
    @Default(0) int inboxWatchingOpenCount,
    @Default(0) int inboxReceiptsOpenCount,
    String? inboxWatchingBeaconId,
  }) = _HomeTabReselectState;

  const HomeTabReselectState._();
}
