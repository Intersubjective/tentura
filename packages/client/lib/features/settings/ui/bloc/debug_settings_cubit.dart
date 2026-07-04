import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/app/platform/platform_info.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';
import 'package:tentura/features/notification/domain/exception.dart';
import 'package:tentura/features/notification/domain/use_case/fcm_case.dart';
import 'package:tentura/features/notification/ui/bloc/fcm_cubit.dart';
import 'package:tentura/features/settings/domain/port/email_test_remote_repository_port.dart';

import '../message/debug_settings_messages.dart';
import 'debug_settings_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'debug_settings_state.dart';

@injectable
class DebugSettingsCubit extends Cubit<DebugSettingsState> {
  DebugSettingsCubit(
    this._fcmCase,
    this._authCase,
    this._fcmCubit,
    this._emailTestRepository,
    this._effects,
  ) : super(const DebugSettingsState());

  final FcmCase _fcmCase;
  final AuthCase _authCase;
  final FcmCubit _fcmCubit;
  final EmailTestRemoteRepositoryPort _emailTestRepository;
  final UiEffectPort _effects;

  Timer? _fcmCooldownTimer;
  Timer? _emailCooldownTimer;

  @override
  Future<void> close() {
    _fcmCooldownTimer?.cancel();
    _emailCooldownTimer?.cancel();
    return super.close();
  }

  Future<void> loadFcmInfo() async {
    emit(state.copyWith(isLoadingFcmInfo: true));
    try {
      final accountId = await _authCase.getCurrentAccountId();
      final info = await _fcmCase.getRegistrationInfo(
        accountId: accountId,
        permissionGranted: _fcmCubit.state.permissions.authorized,
        platform: platformName,
      );
      emit(
        state.copyWith(
          isLoadingFcmInfo: false,
          fcmToken: info.token,
          fcmAppId: info.appId,
          platform: info.platform,
          permissionGranted: info.permissionGranted,
          serverSynced: info.serverSynced,
        ),
      );
    } catch (e) {
      emit(state.copyWith(isLoadingFcmInfo: false));
      _effects.emit(ShowError(e));
    }
  }

  Future<void> sendTestNotification() async {
    if (!state.isFcmTestEnabled) {
      return;
    }
    emit(state.copyWith(isSendingFcm: true));
    try {
      final result = await _fcmCase.sendTestNotification();
      if (result.ok) {
        _startFcmCooldown();
        if (result.mock) {
          _effects.emit(const ShowMessage(DebugFcmTestMockMessage()));
        }
        _effects.emit(
          ShowMessage(
            DebugFcmTestSentMessage(
              sent: result.sent,
              devices: result.devices,
            ),
          ),
        );
      } else {
        _emitFcmFailure(result.reason);
      }
    } catch (e) {
      _effects.emit(ShowError(e));
    } finally {
      if (!isClosed) {
        emit(state.copyWith(isSendingFcm: false));
      }
    }
  }

  Future<void> forceReregisterDevice() async {
    if (!state.isForceReregisterEnabled) {
      return;
    }
    emit(state.copyWith(isForcingReregister: true));
    try {
      await _fcmCubit.forceReregister();
      await loadFcmInfo();
      _effects.emit(const ShowMessage(DebugFcmForceReregisterSentMessage()));
    } on FcmPermissionDeniedException {
      _effects.emit(
        const ShowMessage(DebugFcmForceReregisterPermissionDeniedMessage()),
      );
    } on FcmNoActiveAccountException {
      _effects.emit(
        const ShowMessage(DebugFcmForceReregisterNoAccountMessage()),
      );
    } on FcmRegistrationRejectedException {
      _effects.emit(
        const ShowMessage(DebugFcmForceReregisterRejectedMessage()),
      );
    } catch (e) {
      _effects.emit(ShowError(e));
    } finally {
      if (!isClosed) {
        emit(state.copyWith(isForcingReregister: false));
      }
    }
  }

  Future<void> sendTestEmail() async {
    if (!state.isEmailTestEnabled) {
      return;
    }
    emit(state.copyWith(isSendingEmail: true));
    try {
      final result = await _emailTestRepository.sendTestEmail();
      if (result.ok) {
        _startEmailCooldown();
        if (result.mock) {
          _effects.emit(const ShowMessage(DebugEmailTestMockMessage()));
        }
        _effects.emit(const ShowMessage(DebugEmailTestSentMessage()));
      } else {
        _emitEmailFailure(result.reason);
      }
    } catch (e) {
      _effects.emit(ShowError(e));
    } finally {
      if (!isClosed) {
        emit(state.copyWith(isSendingEmail: false));
      }
    }
  }

  void _emitFcmFailure(String? reason) {
    final message = switch (reason) {
      'rate_limited' => const DebugFcmTestRateLimitedMessage(),
      'no_devices' => const DebugFcmTestNoDevicesMessage(),
      _ => null,
    };
    if (message != null) {
      _effects.emit(ShowMessage(message));
    } else {
      _effects.emit(ShowError(Exception('FCM test failed: $reason')));
    }
  }

  void _emitEmailFailure(String? reason) {
    final message = switch (reason) {
      'rate_limited' => const DebugEmailTestRateLimitedMessage(),
      'no_email' => const DebugEmailTestNoEmailMessage(),
      'send_failed' => const DebugEmailTestFailedMessage(),
      _ => null,
    };
    if (message != null) {
      _effects.emit(ShowMessage(message));
    } else {
      _effects.emit(ShowError(Exception('Email test failed: $reason')));
    }
  }

  void _startFcmCooldown() {
    _fcmCooldownTimer?.cancel();
    final until = DateTime.now().add(kDebugSendCooldown);
    emit(state.copyWith(fcmCooldownUntil: until));
    _fcmCooldownTimer = Timer(kDebugSendCooldown, () {
      if (!isClosed) {
        emit(state.copyWith(fcmCooldownUntil: null));
      }
    });
  }

  void _startEmailCooldown() {
    _emailCooldownTimer?.cancel();
    final until = DateTime.now().add(kDebugSendCooldown);
    emit(state.copyWith(emailCooldownUntil: until));
    _emailCooldownTimer = Timer(kDebugSendCooldown, () {
      if (!isClosed) {
        emit(state.copyWith(emailCooldownUntil: null));
      }
    });
  }
}
