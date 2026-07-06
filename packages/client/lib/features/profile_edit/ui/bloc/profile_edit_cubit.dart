import 'package:get_it/get_it.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'package:tentura/features/profile/domain/port/profile_repository_port.dart';

import 'profile_edit_state.dart';

export 'package:tentura/ui/bloc/state_base.dart';

export 'profile_edit_state.dart';

class ProfileEditCubit extends Cubit<ProfileEditState> {
  // TODO(contract): Phase-2 DTO migration — route multi-repo orchestration through a *Case.
  // ignore: tentura_lints/cubit_requires_use_case_for_multi_repos
  ProfileEditCubit({
    required Profile profile,
    ImageRepository? imageRepository,
    ProfileRepositoryPort? profileRepository,
    UiEffectPort? effects,
  }) : _imageRepository = imageRepository ?? GetIt.I<ImageRepository>(),
       _profileRepository = profileRepository ?? GetIt.I<ProfileRepositoryPort>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
         ProfileEditState(
           original: profile,
           displayName: profile.displayName,
           handle: profile.handle,
           description: profile.description,
           canDropImage: profile.hasAvatar,
         ),
       );

  final ImageRepository _imageRepository;

  final ProfileRepositoryPort _profileRepository;

  final UiEffectPort _effects;

  void _emitSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  //
  void setDisplayName(String value) =>
      emit(state.copyWith(displayName: value));

  //
  void setHandle(String value) => emit(state.copyWith(handle: value));

  //
  void setDescription(String value) => emit(state.copyWith(description: value));

  //
  Future<void> uploadImage(List<PlatformUiSettings> cropUiSettings) async {
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsLoading()));
    }
    try {
      final picked = await _imageRepository.pickAndCropImage(cropUiSettings);
      if (isClosed) {
        return;
      }
      if (picked != null) {
        emit(
          state.copyWith(
            image: picked.toImageEntity(),
            canDropImage: true,
            willDropImage: false,
            status: const StateIsSuccess(),
          ),
        );
      } else {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    } catch (e) {
      if (!isClosed) {
        _emitSnackError(e);
      }
    }
  }

  //
  Future<void> cropCurrentImage(List<PlatformUiSettings> cropUiSettings) async {
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsLoading()));
    }
    try {
      final sourceBytes =
          state.image?.imageBytes ??
          (state.original.hasAvatar
              ? await _imageRepository.fetchImageBytes(
                  state.original.avatarUrl,
                )
              : null);
      if (isClosed) {
        return;
      }
      if (sourceBytes == null) {
        emit(state.copyWith(status: const StateIsSuccess()));
        return;
      }

      final picked = await _imageRepository.cropImageBytes(
        sourceBytes,
        cropUiSettings,
      );
      if (isClosed) {
        return;
      }
      if (picked != null) {
        emit(
          state.copyWith(
            image: picked.toImageEntity(),
            canDropImage: true,
            willDropImage: false,
            status: const StateIsSuccess(),
          ),
        );
      } else {
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    } catch (e) {
      if (!isClosed) {
        _emitSnackError(e);
      }
    }
  }

  //
  void clearImage() => emit(
    state.copyWith(
      status: const StateIsSuccess(),
      image: null,
      canDropImage: false,
      willDropImage: true,
    ),
  );

  //
  Future<void> save() async {
    if (!isClosed) {
      emit(state.copyWith(status: StateStatus.isLoading));
    }
    try {
      await _profileRepository.update(
        state.original,
        displayName: state.displayName,
        updateHandle: true,
        handle: state.handle.trim().toLowerCase(),
        description: state.description,
        dropImage: state.willDropImage,
        image: state.image,
      );
      if (!isClosed) {
        _effects.emit(const NavigateBack());
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    } catch (e) {
      if (!isClosed) {
        _emitSnackError(e);
      }
    }
  }
}
