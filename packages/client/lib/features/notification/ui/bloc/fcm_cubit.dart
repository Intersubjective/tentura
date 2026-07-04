import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/app/platform/platform_info.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import '../../domain/exception.dart';
import '../../domain/use_case/fcm_case.dart';
import '../../fcm_debug_log.dart';
import 'fcm_state.dart';

/// Global Cubit
@singleton
class FcmCubit extends Cubit<FcmState> with WidgetsBindingObserver {
  FcmCubit(
    this._fcmCase,
    this._authCase,
  ) : super(const FcmState()) {
    fcmLog('FcmCubit: constructed platform=$platformName');
    if (kIsWeb) {
      WidgetsBinding.instance.addObserver(this);
    }
    _tokenRefreshSubscription = _fcmCase.onTokenRefresh.listen(
      (token) {
        fcmLog(
          'FcmCubit: onTokenRefresh fingerprint=${fcmTokenFingerprint(token)}',
        );
        if (_activeAccountId.isEmpty) {
          return;
        }
        unawaited(() async {
          try {
            await _syncToken(
              accountId: _activeAccountId,
              token: token,
              forceRegister: true,
            );
          } catch (e, st) {
            fcmLog('FcmCubit: token refresh register failed: $e');
            fcmLog('FcmCubit: stack: $st');
          }
        }());
      },
      cancelOnError: false,
    );
    _currentAccountChangesSubscription =
        _authCase.currentAccountChanges().listen(
      _onAccountChanges,
      cancelOnError: false,
    );
  }

  final FcmCase _fcmCase;

  final AuthCase _authCase;

  late final StreamSubscription<String> _tokenRefreshSubscription;

  late final StreamSubscription<String> _currentAccountChangesSubscription;

  String _activeAccountId = '';

  Timer? _visibilityResyncTimer;

  Timer? _coldStartRetryTimer;

  //
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!kIsWeb || state != AppLifecycleState.resumed) {
      return;
    }
    if (_activeAccountId.isEmpty) {
      return;
    }
    _visibilityResyncTimer?.cancel();
    _visibilityResyncTimer = Timer(const Duration(seconds: 2), () {
      unawaited(() async {
        try {
          await _syncToken(accountId: _activeAccountId);
        } catch (e, st) {
          fcmLog('FcmCubit: visibility resync failed: $e');
          fcmLog('FcmCubit: stack: $st');
        }
      }());
    });
  }

  /// Manual retry for Settings → Debug: bypasses the "already synced" cache
  /// and forces a fresh `fcmTokenRegister` call for the active account, so a
  /// stuck device (stale record, past rejection, ...) doesn't have to wait
  /// out the TTL. Unlike the background paths above, this does not swallow
  /// errors — the caller shows success/failure to the user.
  Future<void> forceReregister() async {
    if (_activeAccountId.isEmpty) {
      throw const FcmNoActiveAccountException();
    }
    final permissions = await _fcmCase.requestPermission();
    emit(state.copyWith(permissions: permissions));
    if (!permissions.authorized) {
      throw const FcmPermissionDeniedException();
    }
    await _syncToken(accountId: _activeAccountId, forceRegister: true);
  }

  @override
  @disposeMethod
  Future<void> close() async {
    fcmLog('FcmCubit: closing');
    _visibilityResyncTimer?.cancel();
    _coldStartRetryTimer?.cancel();
    if (kIsWeb) {
      WidgetsBinding.instance.removeObserver(this);
    }
    await _currentAccountChangesSubscription.cancel();
    await _tokenRefreshSubscription.cancel();
    return super.close();
  }

  Future<void> _onAccountChanges(String accountId) async {
    _activeAccountId = accountId;

    if (accountId.isEmpty) {
      fcmLog('FcmCubit: account cleared, unregistering device');
      try {
        await _fcmCase.unregisterCurrentDevice();
      } catch (e, st) {
        fcmLog('FcmCubit: unregister on clear failed: $e');
        fcmLog('FcmCubit: stack: $st');
      }
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
      final synced = await _syncToken(accountId: accountId);
      if (!synced) {
        _scheduleColdStartRetry(accountId);
      }
    } catch (e, st) {
      fcmLog('FcmCubit: account FCM setup failed: $e');
      fcmLog('FcmCubit: stack: $st');
      if (!isClosed) {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    }
  }

  /// This cubit runs its first sync as soon as the account stream emits —
  /// on web, that can race the Firebase messaging service worker
  /// registration in index.html, which is deferred to `window.load` and
  /// entirely unsynchronized with the Dart app's own boot. When that race
  /// is lost, `getToken()` comes back empty and there's simply no token to
  /// register yet (confirmed live: App ID stayed unset until a manual
  /// "Force re-register" — by then the service worker had long finished —
  /// succeeded outright). One short delayed retry self-heals this without
  /// making the user find that button.
  void _scheduleColdStartRetry(String accountId) {
    _coldStartRetryTimer?.cancel();
    _coldStartRetryTimer = Timer(const Duration(seconds: 3), () {
      unawaited(() async {
        try {
          fcmLog('FcmCubit: cold-start retry accountId=$accountId');
          await _syncToken(accountId: accountId);
        } catch (e, st) {
          fcmLog('FcmCubit: cold-start retry failed: $e');
          fcmLog('FcmCubit: stack: $st');
        }
      }());
    });
  }

  //
  //
  /// Returns false when there's simply no platform token yet (e.g. the
  /// service worker registration in index.html — deferred to `window.load`,
  /// unsynchronized with this cubit's own boot — hasn't completed yet), as
  /// opposed to throwing, which means a real registration attempt failed.
  Future<bool> _syncToken({
    required String accountId,
    String? token,
    bool forceRegister = false,
  }) async {
    fcmLog(
      'FcmCubit: sync start platform=$platformName '
      'incoming=${fcmTokenFingerprint(token)} force=$forceRegister',
    );
    try {
      final appId = await _fcmCase.syncTokenForAccount(
        accountId: accountId,
        platform: platformName,
        token: token,
        forceRegister: forceRegister,
      );
      if (appId == null) {
        return false;
      }
      final resolved = token ?? state.token;
      fcmLog(
        'FcmCubit: sync done appId=$appId '
        'token=${fcmTokenFingerprint(resolved)}',
      );
      emit(
        state.copyWith(
          appId: appId,
          token: resolved,
          status: StateStatus.isSuccess,
        ),
      );
      return true;
    } catch (e, st) {
      fcmLog('FcmCubit: sync failed: $e');
      fcmLog('FcmCubit: stack: $st');
      rethrow;
    }
  }
}
