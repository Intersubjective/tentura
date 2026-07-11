import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';

import '../../data/repository/beacon_repository.dart';
import 'involved_beacon_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'involved_beacon_state.dart';

/// Lists beacons authored by [InvolvedBeaconState.authorId] that were ever
/// forwarded to the current viewer — the "beacons I'm involved in" entry
/// point on another user's profile.
class InvolvedBeaconCubit extends Cubit<InvolvedBeaconState> {
  // TODO(contract): Phase-2 DTO migration — route multi-repo orchestration through a *Case.
  // ignore: tentura_lints/cubit_requires_use_case_for_multi_repos
  InvolvedBeaconCubit({
    required String authorId,
    BeaconRepository? beaconRepository,
    AuthLocalRepositoryPort? authLocalRepository,
    UiEffectPort? effects,
  }) : _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _authLocalRepository =
           authLocalRepository ?? GetIt.I<AuthLocalRepositoryPort>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(InvolvedBeaconState(authorId: authorId)) {
    _beaconChanges = _beaconRepository.changes.listen(
      _onBeaconChanged,
      cancelOnError: false,
    );
  }

  final BeaconRepository _beaconRepository;

  final AuthLocalRepositoryPort _authLocalRepository;

  final UiEffectPort _effects;

  late final StreamSubscription<RepositoryEvent<Beacon>> _beaconChanges;

  @override
  Future<void> close() async {
    await _beaconChanges.cancel();
    return super.close();
  }

  Future<void> fetch({bool reset = false}) async {
    if (!reset && (state.hasReachedLast || state.status is StateIsLoading)) {
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final viewerId = await _authLocalRepository.getCurrentAccountId();
      final offset = reset ? 0 : state.beacons.length;
      final fetched = await _beaconRepository.fetchInvolvedBeacons(
        authorId: state.authorId,
        viewerId: viewerId,
        offset: offset,
      );
      final beacons = fetched.toList();
      emit(
        state.copyWith(
          beacons: reset ? beacons : [...state.beacons, ...beacons],
          hasReachedLast: beacons.length < kFetchWindowSize,
          loadError: null,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      if (state.beacons.isEmpty) {
        emit(state.copyWith(loadError: e, status: const StateIsSuccess()));
      } else {
        _effects.emit(ShowError(e));
        emit(state.copyWith(loadError: null, status: const StateIsSuccess()));
      }
    }
  }

  void _onBeaconChanged(RepositoryEvent<Beacon> event) => switch (event) {
    RepositoryEventUpdate<Beacon>(value: final b) => emit(state.copyWith(
      beacons: [for (final e in state.beacons) e.id == b.id ? b : e],
      status: StateStatus.isSuccess,
    )),
    RepositoryEventDelete<Beacon>(value: final b) => emit(state.copyWith(
      beacons: state.beacons.where((e) => e.id != b.id).toList(),
      status: StateStatus.isSuccess,
    )),
    _ => null,
  };
}
