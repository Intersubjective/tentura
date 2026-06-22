// ignore_for_file: prefer_void_public_cubit_methods

// ignore: avoid_flutter_imports
import 'package:flutter/material.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/env.dart';
import 'package:tentura/domain/port/platform_repository_port.dart';

import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/auth/ui/bloc/auth_cubit.dart';

import '../../domain/port/settings_repository_port.dart';
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
    AuthCubit authCubit,
    AccountCase accountCase,
    PlatformRepositoryPort platformRepository,
    SettingsRepositoryPort settingsRepository,
  ) async {
    final isIntroEnabled = await settingsRepository.getIsIntroEnabled() ?? true;
    final themeModeName =
        await settingsRepository.getThemeModeName() ?? 'system';
    final localePreferenceRaw =
        await settingsRepository.getLocalePreference();
    final localePreference = SettingsState.normalizeLocalePreference(
      localePreferenceRaw,
    );
    return SettingsCubit(
      authCase: authCase,
      authCubit: authCubit,
      accountCase: accountCase,
      settingsRepository: settingsRepository,
      state: SettingsState(
        introEnabled: isIntroEnabled,
        visibleVersion: await platformRepository.getAppVersion(),
        localePreference: localePreference,
        themeMode: ThemeMode.values.firstWhere(
          (themeMode) => themeMode.name == themeModeName,
          orElse: () => ThemeMode.system,
        ),
      ),
    );
  }

  SettingsCubit({
    required this._authCase,
    required this._authCubit,
    required this._accountCase,
    required this._settingsRepository,
    SettingsState state = const SettingsState(),
  }) : super(state);

  final AuthCase _authCase;

  final AuthCubit _authCubit;

  final AccountCase _accountCase;

  final SettingsRepositoryPort _settingsRepository;

  //
  //
  @disposeMethod
  Future<void> dispose() => close();

  //
  //
  Future<String?> tryGetCurrentAccountSeed() async =>
      _accountCase.tryGetSeedForAccount(await _authCase.getCurrentAccountId());

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
  Future<void> setLocalePreference(String localePreference) async {
    if (!kSupportedLocalePreferences.contains(localePreference)) {
      return;
    }
    try {
      await _settingsRepository.setLocalePreference(localePreference);
      emit(state.copyWith(localePreference: localePreference));
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
  Future<void> signOut() => _authCubit.signOut();

  Future<void> resetLocalAuthState() => _authCubit.resetLocalAuthState();

  Future<bool> hasSeedOnlyLocalAccounts() =>
      _authCubit.hasSeedOnlyLocalAccounts();
}
