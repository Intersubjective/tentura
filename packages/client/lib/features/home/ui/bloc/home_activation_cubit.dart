import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/features/home/domain/entity/home_activation.dart';
import 'package:tentura/features/home/domain/port/home_orientation_preferences_port.dart';

import 'home_activation_state.dart';

export 'home_activation_state.dart';

@singleton
final class HomeActivationCubit extends Cubit<HomeActivationState> {
  HomeActivationCubit(this._preferences) : super(const HomeActivationState());

  final HomeOrientationPreferencesPort _preferences;
  int _bindGeneration = 0;

  Future<void> bindAccount(String accountId) async {
    final generation = ++_bindGeneration;
    emit(
      state.copyWith(
        boundAccountId: accountId,
        signals: const HomeActivationSignals(),
        activatedLatch: false,
        dismissedLatch: false,
        hydrated: false,
      ),
    );

    if (accountId.isEmpty) {
      if (generation != _bindGeneration || isClosed) return;
      emit(state.copyWith(hydrated: true));
      return;
    }

    final activated = await _preferences.isActivated(userId: accountId);
    final dismissed = await _preferences.isOrientationDismissed(
      userId: accountId,
    );
    final override = await _preferences.getDebugOverride();

    if (isClosed || generation != _bindGeneration) return;

    emit(
      state.copyWith(
        activatedLatch: activated,
        dismissedLatch: dismissed,
        debugOverride: override,
        hydrated: true,
      ),
    );
  }

  void reportMyWork({
    required String accountId,
    required int myWorkCardCount,
    required int draftCount,
    required int archivedCountHint,
    required bool myWorkLoaded,
  }) {
    if (accountId.isEmpty || accountId != state.boundAccountId) return;
    final previous = state.signals;
    emit(
      state.copyWith(
        signals: HomeActivationSignals(
          myWorkCardCount: myWorkCardCount,
          draftCount: draftCount,
          archivedCountHint: archivedCountHint,
          myWorkLoaded: myWorkLoaded,
          inboxItemCount: previous.inboxItemCount,
          inboxLoaded: previous.inboxLoaded,
          inboxFailed: previous.inboxFailed,
        ),
      ),
    );
    _maybePersistActivation();
  }

  void reportInbox({
    required String accountId,
    required int inboxItemCount,
    required bool inboxLoaded,
    required bool inboxFailed,
  }) {
    if (accountId.isEmpty || accountId != state.boundAccountId) return;
    final previous = state.signals;
    emit(
      state.copyWith(
        signals: HomeActivationSignals(
          myWorkCardCount: previous.myWorkCardCount,
          draftCount: previous.draftCount,
          archivedCountHint: previous.archivedCountHint,
          myWorkLoaded: previous.myWorkLoaded,
          inboxItemCount: inboxItemCount,
          inboxLoaded: inboxLoaded,
          inboxFailed: inboxFailed,
        ),
      ),
    );
    _maybePersistActivation();
  }

  Future<void> dismiss() async {
    final userId = state.boundAccountId;
    if (userId.isEmpty) return;
    emit(state.copyWith(dismissedLatch: true));
    await _preferences.setOrientationDismissed(userId: userId);
  }

  Future<void> setDebugOverride(OrientationDebugOverride value) async {
    await _preferences.setDebugOverride(value);
    if (isClosed) return;
    emit(state.copyWith(debugOverride: value));
  }

  Future<void> resetFirstRunState() async {
    final userId = state.boundAccountId;
    if (userId.isEmpty) return;
    await _preferences.resetFirstRunState(userId: userId);
    if (isClosed) return;
    emit(
      state.copyWith(
        activatedLatch: false,
        dismissedLatch: false,
      ),
    );
  }

  void _maybePersistActivation() {
    if (!state.signals.hasProvenActivity || state.activatedLatch) return;
    final userId = state.boundAccountId;
    if (userId.isEmpty) return;
    emit(state.copyWith(activatedLatch: true));
    unawaited(_preferences.setActivated(userId: userId));
  }
}
