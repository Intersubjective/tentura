import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/auth/data/repository/auth_local_repository.dart';

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
    AuthLocalRepository? authLocalRepository,
  }) : _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _authLocalRepository =
           authLocalRepository ?? GetIt.I<AuthLocalRepository>(),
       super(
         BeaconState(
           beacons: [],
           profileId: profileId,
         ),
       );

  final BeaconRepository _beaconRepository;

  final AuthLocalRepository _authLocalRepository;

  Future<void> fetch() async {
    if (state.hasReachedLast || state.status is StateIsLoading) {
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final myAccountId = await _authLocalRepository.getCurrentAccountId();
      final beacons = await _beaconRepository.fetchBeacons(
        isEnabled: state.filter == BeaconFilter.enabled,
        offset: state.beacons.length,
        profileId: state.profileId,
      );
      emit(
        state.copyWith(
          isMine: myAccountId == state.profileId,
          beacons: state.beacons..addAll(beacons),
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

  Future<void> delete(String beaconId) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _beaconRepository.delete(beaconId);
      state.beacons.removeWhere((e) => e.id == beaconId);
      emit(state.copyWith(status: StateStatus.isSuccess));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> toggleEnabled(String beaconId) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final beaconIndex = state.beacons.indexWhere((e) => e.id == beaconId);
      final beacon = state.beacons[beaconIndex];
      await _beaconRepository.setEnabled(
        !beacon.isEnabled,
        id: beacon.id,
      );
      state.beacons[beaconIndex] = beacon.copyWith(
        isEnabled: !beacon.isEnabled,
      );
      emit(state.copyWith(status: StateStatus.isSuccess));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
