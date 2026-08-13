import 'package:get_it/get_it.dart';

import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'routing_mute_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'routing_mute_state.dart';

class RoutingMuteCubit extends Cubit<RoutingMuteState> {
  RoutingMuteCubit({
    CapabilityRepositoryPort? repository,
    UiEffectPort? effects,
  }) : _repository = repository ?? GetIt.I<CapabilityRepositoryPort>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(RoutingMuteState());

  final CapabilityRepositoryPort _repository;
  final UiEffectPort _effects;

  Future<void> fetch() async {
    emit(state.copyWith(status: const StateIsLoading()));
    try {
      final muted = await _repository.fetchMyRoutingTags();
      emit(
        state.copyWith(
          mutedSlugs: muted.toSet(),
          status: const StateIsSuccess(),
        ),
      );
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  Future<void> toggleMute({required String slug, required bool muted}) async {
    final previous = state.mutedSlugs;
    final next = Set<String>.from(previous);
    if (muted) {
      next.add(slug);
    } else {
      next.remove(slug);
    }
    emit(state.copyWith(mutedSlugs: next, status: const StateIsSuccess()));
    try {
      await _repository.setRoutingMute(slug: slug, muted: muted);
    } catch (e) {
      emit(state.copyWith(mutedSlugs: previous));
      _effects.emit(ShowError(e));
    }
  }
}
