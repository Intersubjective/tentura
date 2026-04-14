import 'package:freezed_annotation/freezed_annotation.dart';

part 'app_update_state.freezed.dart';

@freezed
abstract class AppUpdateState with _$AppUpdateState {
  const factory AppUpdateState({
    @Default(false) bool updateAvailable,
    @Default(false) bool dismissed,
    @Default('') String minVersion,
  }) = _AppUpdateState;

  const AppUpdateState._();
}
