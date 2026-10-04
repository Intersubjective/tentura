import 'package:get_it/get_it.dart';

import 'package:tentura/domain/port/trust_preference_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'noisy_wall_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'noisy_wall_state.dart';

class NoisyWallCubit extends Cubit<NoisyWallState> {
  NoisyWallCubit({
    TrustPreferenceRepositoryPort? repository,
    UiEffectPort? effects,
  }) : _repository = repository ?? GetIt.I<TrustPreferenceRepositoryPort>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(const NoisyWallState());

  final TrustPreferenceRepositoryPort _repository;
  final UiEffectPort _effects;

  Future<void> fetch() async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final enabled = await _repository.fetchNoisyWallEnabled();
      emit(NoisyWallState(enabled: enabled, status: const StateIsSuccess()));
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  /// Optimistic: shows [enabled] at once, rolls back if the server refuses.
  Future<void> set({required bool enabled}) async {
    final previous = state.enabled;
    emit(NoisyWallState(enabled: enabled, status: const StateIsSuccess()));
    try {
      final stored = await _repository.setNoisyWallEnabled(enabled: enabled);
      emit(NoisyWallState(enabled: stored, status: const StateIsSuccess()));
    } catch (e) {
      emit(NoisyWallState(enabled: previous, status: const StateIsSuccess()));
      _effects.emit(ShowError(e));
    }
  }
}
