import 'state_base.dart';

part 'screen_state.freezed.dart';

@freezed
abstract class ScreenState extends StateBase with _$ScreenState {
  const factory ScreenState({
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ScreenState;

  const ScreenState._();
}
