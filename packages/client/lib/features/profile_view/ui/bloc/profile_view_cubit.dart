import 'dart:async';
import 'package:get_it/get_it.dart';

import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/domain/port/capability_repository_port.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import 'package:tentura/features/like/data/repository/like_remote_repository.dart';
import 'package:tentura/features/opinion/data/repository/opinion_repository.dart';
import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import 'profile_view_state.dart';

export 'package:flutter_bloc/flutter_bloc.dart';

export 'profile_view_state.dart';

class ProfileViewCubit extends Cubit<ProfileViewState> {
  // TODO(contract): Phase-2 DTO migration — route multi-repo orchestration through a *Case.
  // ignore: cubit_requires_use_case_for_multi_repos
  ProfileViewCubit({
    required String id,
    ProfileRepositoryPort? profileRepository,
    LikeRemoteRepository? likeRemoteRepository,
    CapabilityRepositoryPort? capabilityRepository,
  }) : _profileRepository = profileRepository ?? GetIt.I<ProfileRepositoryPort>(),
       _likeRemoteRepository =
           likeRemoteRepository ?? GetIt.I<LikeRemoteRepository>(),
       _capabilityRepository =
           capabilityRepository ?? GetIt.I<CapabilityRepositoryPort>(),
       super(switch (id) {
         _ when id.startsWith('O') => ProfileViewState(focusOpinionId: id),
         _ when id.startsWith('U') => ProfileViewState(
           profile: Profile(id: id),
         ),
         _ => ProfileViewState(status: StateHasError('Wrong id: $id')),
       }) {
    unawaited(fetch());
    _capabilitySub = _capabilityRepository.changes.listen(
      (_) => unawaited(_refreshCues()),
    );
  }

  final ProfileRepositoryPort _profileRepository;
  final LikeRemoteRepository _likeRemoteRepository;
  final CapabilityRepositoryPort _capabilityRepository;

  late final StreamSubscription<void> _capabilitySub;

  @override
  Future<void> close() async {
    await _capabilitySub.cancel();
    return super.close();
  }

  Future<void> fetch() async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      String profileId;
      if (state.profile.isEmpty && state.focusOpinionId.isNotEmpty) {
        final opinion = await GetIt.I<OpinionRepository>().fetchById(
          state.focusOpinionId,
        );
        profileId = opinion.objectId;
        emit(
          state.copyWith(
            status: StateStatus.isSuccess,
            profile: await _profileRepository.fetchById(profileId),
          ),
        );
      } else {
        profileId = state.profile.id;
        emit(
          state.copyWith(
            status: StateStatus.isSuccess,
            profile: await _profileRepository.fetchById(profileId),
          ),
        );
      }
      await _refreshCues();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> _refreshCues() async {
    final profileId = state.profile.id;
    if (profileId.isEmpty) return;
    try {
      final cues = await _capabilityRepository.fetchCues(profileId);
      if (!isClosed) emit(state.copyWith(cues: cues));
    } catch (_) {
      // Cues are non-critical; don't surface errors to the user.
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

  void updatePrivateLabels(List<String> slugs) {
    emit(
      state.copyWith(
        cues: state.cues.copyWith(privateLabels: slugs),
      ),
    );
  }
}
