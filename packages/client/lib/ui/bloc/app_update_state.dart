import 'package:tentura/ui/bloc/state_base.dart';

part 'app_update_state.freezed.dart';

@freezed
abstract class AppUpdateState extends StateBase with _$AppUpdateState {
  const factory AppUpdateState({
    @Default(StateIsSuccess()) StateStatus status,
    @Default(false) bool updateAvailable,
    @Default(false) bool dismissed,
    @Default('') String minVersion,
  }) = _AppUpdateState;

  const AppUpdateState._();
}
