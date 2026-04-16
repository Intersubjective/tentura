import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/auth/domain/port/auth_local_repository_port.dart';

import '../../data/repository/beacon_repository.dart';
import '../../domain/enum.dart';
import 'beacon_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'beacon_state.dart';

class BeaconCubit extends Cubit<BeaconState> {
  BeaconCubit({
    required String profileId,
    BeaconRepository? beaconRepository,
    AuthLocalRepositoryPort? authLocalRepository,
  }) : _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _authLocalRepository =
           authLocalRepository ?? GetIt.I<AuthLocalRepositoryPort>(),
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
      final lifecycleStates = state.filter == BeaconFilter.active
          ? [
              BeaconLifecycle.open.smallintValue,
              BeaconLifecycle.draft.smallintValue,
              BeaconLifecycle.pendingReview.smallintValue,
              BeaconLifecycle.closedReviewOpen.smallintValue,
            ]
          : [
              BeaconLifecycle.closed.smallintValue,
              BeaconLifecycle.deleted.smallintValue,
              BeaconLifecycle.closedReviewComplete.smallintValue,
            ];
      final offset = reset ? 0 : state.beacons.length;
      final beacons = await _beaconRepository.fetchBeacons(
        lifecycleStates: lifecycleStates,
        offset: offset,
        profileId: state.profileId,
      );
      emit(
        state.copyWith(
          isMine: myAccountId == state.profileId,
          beacons: reset ? beacons.toList() : (state.beacons..addAll(beacons)),
          hasReachedLast: beacons.length < kFetchWindowSize,
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
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
