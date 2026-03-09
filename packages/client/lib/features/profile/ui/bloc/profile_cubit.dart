import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import '../../data/repository/profile_repository.dart';
import 'profile_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'profile_state.dart';

/// Global Cubit
@singleton
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required AuthCase authCase,
    required ProfileRepository profileRepository,
  }) : _profileRepository = profileRepository,
       super(const ProfileState()) {
    _authChanges = authCase.currentAccountChanges().listen(
      _onAuthChanges,
      cancelOnError: false,
    );
    _profileChanges = profileRepository.changes.listen(
      _onProfileChanges,
      cancelOnError: false,
    );
  }

  final ProfileRepository _profileRepository;

  late final StreamSubscription<String> _authChanges;

  late final StreamSubscription<RepositoryEvent<Profile>> _profileChanges;

  //
  //
  @disposeMethod
  Future<void> dispose() async {
    await _authChanges.cancel();
    await _profileChanges.cancel();
    return super.close();
  }

  //
  //
  Future<void> fetch() async {
    if (state.profile.id.isEmpty) {
      return;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final profile = await _profileRepository.fetchById(state.profile.id);
      emit(ProfileState(profile: profile));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> delete() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _profileRepository.delete(state.profile.id);
      emit(const ProfileState(status: StateIsNavigating(kPathSignIn)));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  //
  //
  Future<void> _onAuthChanges(String id) async {
    emit(ProfileState(profile: Profile(id: id)));
    if (id.isNotEmpty) {
      await fetch();
    }
  }

  //
  //
  void _onProfileChanges(RepositoryEvent<Profile> event) => switch (event) {
    RepositoryEventFetch<Profile>(value: final profile)
        when profile.id == state.profile.id =>
      emit(ProfileState(profile: profile)),
    RepositoryEventUpdate<Profile>(value: final profile) => emit(
      ProfileState(profile: profile),
    ),
    _ => null,
  };
}
