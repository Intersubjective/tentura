import 'package:tentura_root/domain/entity/localizable.dart';

import 'state_base.dart';

part 'screen_state.freezed.dart';

@freezed
abstract class ScreenState extends StateBase with _$ScreenState {
  const factory ScreenState({
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ScreenState;

  const ScreenState._();

  ScreenState navigateTo(String path) =>
      copyWith(status: StateIsNavigating(path));

  ScreenState navigateBack() =>
      copyWith(status: StateIsNavigating.back);

  ScreenState messaging(LocalizableMessage message) =>
      copyWith(status: StateIsMessaging(message));
}
