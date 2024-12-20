import 'dart:async';
import 'package:get_it/get_it.dart';
import 'package:injectable/injectable.dart';

import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/profile.dart';
import '../../domain/use_case/profile_case.dart';
import 'profile_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';
export 'package:get_it/get_it.dart';

export 'profile_state.dart';

@lazySingleton
class ProfileCubit extends Cubit<ProfileState> {
  ProfileCubit({
    required String id,
    bool fromCache = true,
    ProfileCase? profileCase,
  })  : _profileCase = profileCase ?? GetIt.I<ProfileCase>(),
        super(ProfileState(profile: Profile(id: id))) {
    fetch(fromCache: fromCache);
  }

  @factoryMethod
  ProfileCubit.global({
    required ProfileCase profileCase,
  })  : _profileCase = profileCase,
        super(const ProfileState()) {
    _authChanges = _profileCase.currentAccountChanges.listen(
      (id) async {
        emit(ProfileState(
          profile: Profile(id: id),
          status: FetchStatus.isLoading,
        ));
        if (kDebugMode) print('Current User Id: $id');
        if (id.isNotEmpty) await fetch(fromCache: true);
      },
      cancelOnError: false,
    );
  }

  final ProfileCase _profileCase;

  StreamSubscription<String>? _authChanges;

  @override
  @disposeMethod
  Future<void> close() async {
    await _authChanges?.cancel();
    return super.close();
  }

  bool checkIfIsMe(String id) => id == state.profile.id;

  bool checkIfIsNotMe(String id) => id != state.profile.id;

  Future<void> fetch({bool fromCache = false}) async {
    if (state.profile.id.isEmpty) return;
    emit(state.setLoading());
    try {
      emit(ProfileState(
        profile: await _profileCase.fetch(
          state.profile.id,
          fromCache: fromCache,
        ),
      ));
    } catch (e) {
      emit(state.setError(e));
    }
  }

  Future<void> update(Profile profile) async {
    if (profile == state.profile) return;
    emit(state.setLoading());
    try {
      emit(ProfileState(profile: await _profileCase.update(profile)));
    } catch (e) {
      emit(state.setError(e));
    }
  }

  Future<void> delete() async {
    emit(state.setLoading());
    try {
      await _profileCase.delete(state.profile.id);
      emit(const ProfileState());
    } catch (e) {
      emit(state.setError(e));
    }
  }

  Future<void> putAvatarImage(Uint8List image) async {
    emit(state.setLoading());
    try {
      await _profileCase.putAvatarImage(image);
      emit(ProfileState(profile: state.profile));
    } catch (e) {
      emit(state.setError(e));
    }
  }
}
