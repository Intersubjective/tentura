// TBD: move not void public methods into state
// ignore_for_file: prefer_void_public_cubit_methods

// TBD: return string instead of ThemeMode?
// ignore: avoid_flutter_imports
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/env.dart';
import 'package:tentura/data/repository/platform_repository.dart';

import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import '../../data/repository/settings_repository.dart';
import 'settings_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'settings_state.dart';

/// Global Cubit
@singleton
class SettingsCubit extends Cubit<SettingsState> {
  @FactoryMethod(preResolve: true)
  static Future<SettingsCubit> hydrated(
    Env env,
    AuthCase authCase,
    AccountCase accountCase,
    PlatformRepository platformRepository,
    SettingsRepository settingsRepository,
  ) async {
    final isIntroEnabled = await settingsRepository.getIsIntroEnabled() ?? true;
    final themeModeName =
        await settingsRepository.getThemeModeName() ?? 'system';
    return SettingsCubit(
      authCase: authCase,
      accountCase: accountCase,
      settingsRepository: settingsRepository,
      state: SettingsState(
        introEnabled: isIntroEnabled,
        visibleVersion: await platformRepository.getAppVersion(),
        themeMode: ThemeMode.values.firstWhere(
          (themeMode) => themeMode.name == themeModeName,
          orElse: () => ThemeMode.system,
        ),
      ),
    );
  }

  SettingsCubit({
    required AuthCase authCase,
    required AccountCase accountCase,
    required SettingsRepository settingsRepository,
    SettingsState state = const SettingsState(),
  }) : _authCase = authCase,
       _accountCase = accountCase,
       _settingsRepository = settingsRepository,
       super(state);

  final AuthCase _authCase;

  final AccountCase _accountCase;

  final SettingsRepository _settingsRepository;

  //
  //
  @disposeMethod
  Future<void> dispose() => close();

  //
  //
  Future<String> getCurrentAccountSeed() async =>
      _accountCase.getSeedByAccountId(await _authCase.getCurrentAccountId());

  //
  //
  Future<void> setThemeMode(ThemeMode themeMode) async {
    try {
      await _settingsRepository.setThemeMode(themeMode.name);
      emit(state.copyWith(themeMode: themeMode));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> setIntroEnabled(bool isEnabled) async {
    try {
      await _settingsRepository.setIsIntroEnabled(isEnabled);
      emit(state.copyWith(introEnabled: isEnabled));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> signOut() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _authCase.signOut();
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
