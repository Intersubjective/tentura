import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/opinion/data/repository/opinion_repository.dart';
import 'package:tentura/features/profile/data/repository/profile_repository.dart';

import 'profile_view_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'profile_view_state.dart';

class ProfileViewCubit extends Cubit<ProfileViewState> {
  ProfileViewCubit({
    required String id,
    ProfileRepository? profileRepository,
    LikeRemoteRepository? likeRemoteRepository,
  }) : _profileRepository = profileRepository ?? GetIt.I<ProfileRepository>(),
       _likeRemoteRepository =
           likeRemoteRepository ?? GetIt.I<LikeRemoteRepository>(),
       super(switch (id) {
         _ when id.startsWith('O') => ProfileViewState(focusOpinionId: id),
         _ when id.startsWith('U') => ProfileViewState(
           profile: Profile(id: id),
         ),
         _ => ProfileViewState(status: StateHasError('Wrong id: $id')),
       }) {
    unawaited(fetch());
  }

  final ProfileRepository _profileRepository;

  final LikeRemoteRepository _likeRemoteRepository;

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      if (state.profile.isEmpty && state.focusOpinionId.isNotEmpty) {
        final opinion = await GetIt.I<OpinionRepository>().fetchById(
          state.focusOpinionId,
        );
        emit(
          state.copyWith(
            status: StateStatus.isSuccess,
            profile: await _profileRepository.fetchById(opinion.objectId),
          ),
        );
      } else {
        emit(
          state.copyWith(
            status: StateStatus.isSuccess,
            profile: await _profileRepository.fetchById(state.profile.id),
          ),
        );
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> addFriend() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      emit(
        state.copyWith(
          profile: await _likeRemoteRepository.setLike(
            state.profile,
            amount: 1,
          ),
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> removeFriend() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      emit(
        state.copyWith(
          profile: await _likeRemoteRepository.setLike(
            state.profile,
            amount: 0,
          ),
          status: StateStatus.isSuccess,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
