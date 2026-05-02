import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../data/repository/profile_shared_beacons_repository.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export '../../data/repository/profile_shared_beacons_repository.dart'
    show
        ProfileCoCommittedEntry,
        ProfileForwardedBeaconEntry,
        ProfileSharedBeaconsData,
        TargetBeaconReaction;

part 'profile_shared_beacons_cubit.freezed.dart';

@freezed
abstract class ProfileSharedBeaconsState extends StateBase
    with _$ProfileSharedBeaconsState {
  const factory ProfileSharedBeaconsState({
    @Default(StateIsSuccess()) StateStatus status,
    ProfileSharedBeaconsData? data,
  }) = _ProfileSharedBeaconsState;

  const ProfileSharedBeaconsState._();
}

class ProfileSharedBeaconsCubit extends Cubit<ProfileSharedBeaconsState> {
  ProfileSharedBeaconsCubit({
    required String meId,
    required String targetId,
    ProfileSharedBeaconsRepository? repository,
  }) : _meId = meId,
       _targetId = targetId,
       _repository = repository ?? GetIt.I<ProfileSharedBeaconsRepository>(),
       super(const ProfileSharedBeaconsState()) {
    unawaited(fetch());
  }

  final String _meId;
  final String _targetId;
  final ProfileSharedBeaconsRepository _repository;

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final data = await _repository.fetch(meId: _meId, targetId: _targetId);
      emit(state.copyWith(status: StateStatus.isSuccess, data: data));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
