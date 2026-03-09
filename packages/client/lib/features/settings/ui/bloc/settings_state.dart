import 'package:flutter/material.dart';

import 'package:tentura/ui/bloc/state_base.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'settings_state.freezed.dart';

@freezed
abstract class SettingsState extends StateBase with _$SettingsState {
  const factory SettingsState({
    String? visibleVersion,
    @Default('en') String locale,
    @Default(true) bool introEnabled,
    @Default(ThemeMode.system) ThemeMode themeMode,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _SettingsState;

  const SettingsState._();
}
