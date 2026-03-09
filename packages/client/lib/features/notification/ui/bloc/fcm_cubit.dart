import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/app/platform/platform_info.dart';

import '../../domain/use_case/fcm_case.dart';
import 'fcm_state.dart';

/// Global Cubit
@singleton
class FcmCubit extends Cubit<FcmState> {
  FcmCubit(
    this._fcmCase,
  ) : super(const FcmState()) {
    _tokenRefreshSubscription = _fcmCase.onTokenRefresh.listen(
      _registerFcmToken,
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
    await _currentAccountChangesSubscription.cancel();
    await _tokenRefreshSubscription.cancel();
    return super.close();
  }

  //
  //
  Future<void> _onAccountChanges(String accountId) async {
    if (accountId.isEmpty) {
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final permissions = await _fcmCase.requestPermission();
      emit(
        state.copyWith(
          permissions: permissions,
        ),
      );
      if (permissions.authorized &&
          await _fcmCase.checkIfRegistrationNeeded()) {
        await _registerFcmToken();
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> _registerFcmToken([String? token]) async {
    final appId = await _fcmCase.registerFcmToken(
      token: token,
      platform: platformName,
    );
    emit(
      state.copyWith(
        appId: appId,
        token: token,
        status: StateStatus.isSuccess,
      ),
    );
  }
}
