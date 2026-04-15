import 'package:freezed_annotation/freezed_annotation.dart';

part 'home_tab_reselect_state.freezed.dart';

@freezed
abstract class HomeTabReselectState with _$HomeTabReselectState {
  const factory HomeTabReselectState({
    @Default(0) int inboxReselectCount,
    @Default(0) int myWorkReselectCount,
  }) = _HomeTabReselectState;
}
