import 'dart:async';

import 'package:injectable/injectable.dart';

import 'package:tentura/app/platform/platform_info.dart';

import '../../domain/use_case/fcm_case.dart';
import '../../fcm_debug_log.dart';
import 'fcm_state.dart';

/// Global Cubit
@singleton
class FcmCubit extends Cubit<FcmState> {
  FcmCubit(
    this._fcmCase,
  ) : super(const FcmState()) {
    fcmLog('FcmCubit: constructed platform=$platformName');
    _tokenRefreshSubscription = _fcmCase.onTokenRefresh.listen(
      (token) {
        fcmLog(
          'FcmCubit: onTokenRefresh fingerprint=${fcmTokenFingerprint(token)}',
        );
        unawaited(() async {
          try {
            await _registerFcmToken(token);
          } catch (e, st) {
            fcmLog('FcmCubit: token refresh register failed: $e');
            fcmLog('FcmCubit: stack: $st');
          }
        }());
      },
      cancelOnError: false,
    );
    _currentAccountChangesSubscription = _fcmCase.currentAccountChanges.listen(
      _onAccountChanges,
      cancelOnError: false,
    );
  }

  final FcmCase _fcmCase;

  late final StreamSubscription<String> _tokenRefreshSubscription;

  late final StreamSubscription<String> _currentAccountChangesSubscription;

  //
  @override
  @disposeMethod
  Future<void> close() async {
    fcmLog('FcmCubit: closing');
    await _currentAccountChangesSubscription.cancel();
    await _tokenRefreshSubscription.cancel();
    return super.close();
  }

  //
  //
  Future<void> _onAccountChanges(String accountId) async {
    if (accountId.isEmpty) {
      fcmLog('FcmCubit: account cleared, skipping FCM');
      return;
    }

    fcmLog('FcmCubit: account changed accountId=$accountId');

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final permissions = await _fcmCase.requestPermission();
      emit(
        state.copyWith(
          permissions: permissions,
        ),
      );
      fcmLog(
        'FcmCubit: permission authorized=${permissions.authorized}',
      );
      if (!permissions.authorized) {
        return;
      }
      // Always sync current getToken() to the server on account activation.
      // Relying only on local fcmTokenUpdatedAt (30d) skips re-register after
      // SW/token rotation, re-import, or embedded browsers — server then keeps
      // a stale token and FCM returns UNREGISTERED for pushes.
      fcmLog('FcmCubit: register (always on account change after permission)');
      await _registerFcmToken();
    } catch (e, st) {
      fcmLog('FcmCubit: account FCM setup failed: $e');
      fcmLog('FcmCubit: stack: $st');
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> _registerFcmToken([String? token]) async {
    fcmLog(
      'FcmCubit: register start platform=$platformName '
      'incoming=${fcmTokenFingerprint(token)}',
    );
    try {
      final appId = await _fcmCase.registerFcmToken(
        token: token,
        platform: platformName,
      );
      final resolved = token ?? state.token;
      fcmLog(
        'FcmCubit: register done appId=$appId '
        'token=${fcmTokenFingerprint(resolved)}',
      );
      emit(
        state.copyWith(
          appId: appId,
          token: resolved,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e, st) {
      fcmLog('FcmCubit: register failed: $e');
      fcmLog('FcmCubit: stack: $st');
      rethrow;
    }
  }
}
