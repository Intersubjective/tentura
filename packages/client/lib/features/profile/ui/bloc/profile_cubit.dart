import 'dart:async';
import 'package:injectable/injectable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/entity/repository_event.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/auth/domain/use_case/account_case.dart';
import 'package:tentura/features/auth/domain/use_case/auth_case.dart';

import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import '../../domain/port/profile_repository_port.dart';
import 'profile_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'profile_state.dart';

/// Global Cubit
@singleton
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required this._accountCase,
    required AuthCase authCase,
    required ProfileRepositoryPort profileRepository,
    required UiEffectPort effects,
  }) : _profileRepository = profileRepository,
       _effects = effects,
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

  final AccountCase _accountCase;

  final ProfileRepositoryPort _profileRepository;

  final UiEffectPort _effects;

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
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  //
  //
  Future<void> delete() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      await _profileRepository.delete(state.profile.id);
      _effects.emit(NavigatePush(kPathSignIn));
      emit(const ProfileState());
    } catch (e) {
      _effects.emit(ShowError(e));
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  //
  //
  Future<void> _onAuthChanges(String id) async {
    if (id.isEmpty) {
      emit(const ProfileState());
      return;
    }
    final account = await _accountCase.getAccountById(id);
    emit(
      ProfileState(
        profile: account != null
            ? AccountCase.fromAccountEntity(account)
            : Profile(id: id),
      ),
    );
    await fetch();
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
