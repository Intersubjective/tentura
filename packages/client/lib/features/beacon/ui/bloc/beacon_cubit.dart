import 'dart:async';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';

import '../../data/repository/beacon_repository.dart';
import '../../domain/enum.dart';
import 'beacon_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'beacon_state.dart';

class BeaconCubit extends Cubit<BeaconState> {
  // TODO(contract): Phase-2 DTO migration — route multi-repo orchestration through a *Case.
  // ignore: tentura_lints/cubit_requires_use_case_for_multi_repos
  BeaconCubit({
    required String profileId,
    BeaconRepository? beaconRepository,
    AuthLocalRepositoryPort? authLocalRepository,
    UiEffectPort? effects,
  }) : _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _authLocalRepository =
           authLocalRepository ?? GetIt.I<AuthLocalRepositoryPort>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
         BeaconState(
           beacons: [],
           profileId: profileId,
         ),
       ) {
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
      final myAccountId = await _authLocalRepository.getCurrentAccountId();
      final isMine = myAccountId == state.profileId;
      final lifecycleStates = state.filter == BeaconFilter.active
          ? [
              BeaconStatus.open.smallintValue,
              BeaconStatus.needsMoreHelp.smallintValue,
              BeaconStatus.enoughHelp.smallintValue,
              if (isMine) BeaconStatus.draft.smallintValue,
              BeaconStatus.reviewOpen.smallintValue,
            ]
          : [
              BeaconStatus.cancelled.smallintValue,
              BeaconStatus.closed.smallintValue,
              BeaconStatus.deleted.smallintValue,
            ];
      final offset = reset ? 0 : state.beacons.length;
      final fetched = await _beaconRepository.fetchBeacons(
        lifecycleStates: lifecycleStates,
        offset: offset,
        profileId: state.profileId,
      );
      final beacons = fetched.where((b) => b.canReadContent).toList();
      emit(
        state.copyWith(
          isMine: isMine,
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

  void setFilter(BeaconFilter? filter) {
    if (filter != null) {
      emit(
        state.copyWith(
          filter: filter,
          hasReachedLast: false,
          beacons: [],
        ),
      );
      unawaited(fetch());
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
    RepositoryEventInvalidate<Beacon>() when state.isMine => _refetchAll(),
    _ => null,
  };

  void _refetchAll() => unawaited(fetch(reset: true));
}
