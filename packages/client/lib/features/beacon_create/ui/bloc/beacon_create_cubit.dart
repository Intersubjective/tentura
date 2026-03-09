import 'package:get_it/get_it.dart';

import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/polling.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';

import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';

import '../message/beacon_create_message.dart';
import 'beacon_create_state.dart';

export 'package:tentura/ui/bloc/state_base.dart';

export 'beacon_create_state.dart';

class BeaconCreateCubit extends Cubit<BeaconCreateState> {
  BeaconCreateCubit({
    ImageRepository? imageRepository,
    BeaconRepository? beaconRepository,
  }) : _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _imageRepository = imageRepository ?? GetIt.I<ImageRepository>(),
       super(
         BeaconCreateState(
           variants: ['', ''],
           variantsKeys: [UniqueKey(), UniqueKey()],
         ),
       );

  final BeaconRepository _beaconRepository;

  final ImageRepository _imageRepository;

  ///
  ///
  void setTitle(String value) => emit(state.copyWith(title: value));

  ///
  ///
  void setDescription(String value) => emit(state.copyWith(description: value));

  ///
  ///
  void setDateRange({DateTime? startAt, DateTime? endAt}) => emit(
    state.copyWith(
      startAt: startAt,
      endAt: endAt,
    ),
  );

  ///
  ///
  void setLocation(Coordinates? value, String locationName) => emit(
    state.copyWith(
      coordinates: value,
      location: locationName,
    ),
  );

  ///
  ///
  Future<void> pickImage() async {
    try {
      final image = await _imageRepository.pickImage();
      if (image != null) {
        emit(state.copyWith(image: image));
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  ///
  void clearImage() => emit(
    state.copyWith(
      image: null,
    ),
  );

  ///
  ///
  void setQuestion(String value) => emit(
    state.copyWith(
      question: value,
    ),
  );

  ///
  ///
  void addVariant() => emit(
    state.copyWith(
      variants: [...state.variants, ''],
      variantsKeys: [...state.variantsKeys, UniqueKey()],
    ),
  );

  ///
  ///
  void removeVariant(int index) {
    emit(
      state.copyWith(
        variants: [...state.variants]..removeAt(index),
        variantsKeys: [...state.variantsKeys]..removeAt(index),
      ),
    );
    validate();
  }

  ///
  ///
  void setVariant(int index, String value) => state.variants[index] = value;

  ///
  ///
  void addTag(String value) => emit(
    state.copyWith(
      tags: {...state.tags, value.toLowerCase()},
    ),
  );

  ///
  ///
  void removeTag(String value) => emit(
    state.copyWith(
      tags: {...state.tags}..remove(value),
    ),
  );

  ///
  ///
  void validate([bool formValid = false]) {
    var canPublish = formValid;

    if (canPublish && state.hasPolling) {
      try {
        if (state.variants.where((e) => e.isNotEmpty).length < 2) {
          throw const PollingTooFewVariantsException();
        }
        Polling.questionValidator(state.question);
        state.variants.forEach(Polling.variantValidator);
      } catch (_) {
        canPublish = false;
      }
    }

    if (state.canTryToPublish != canPublish) {
      emit(state.copyWith(canTryToPublish: canPublish));
    }
  }

  ///
  ///
  Future<void> publish({required String context}) async {
    final variants = state.variants.where((e) => e.isNotEmpty).toList();
    final hasPolling = state.question.isNotEmpty && variants.isNotEmpty;
    if (hasPolling) {
      if (state.question.length < Polling.questionMinLength) {
        return emit(
          state.copyWith(
            status: StateHasError(const PollingQuestionTooShortException()),
          ),
        );
      }
      if (variants.length < 2) {
        return emit(
          state.copyWith(
            status: StateHasError(const PollingTooFewVariantsException()),
          ),
        );
      }
      if (variants.toSet().length != variants.length) {
        return emit(
          state.copyWith(
            status: StateHasError(const PollingVariantsNotUniqueException()),
          ),
        );
      }
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final now = DateTime.timestamp();
      final beacon = await _beaconRepository.create(
        Beacon(
          createdAt: now,
          updatedAt: now,
          context: context,
          tags: state.tags,
          title: state.title,
          coordinates: state.coordinates,
          description: state.description,
          startAt: state.startAt,
          endAt: state.endAt,
          image: state.image,
          polling: hasPolling
              ? Polling(
                  createdAt: now,
                  updatedAt: now,
                  question: state.question,
                  variants: {
                    for (var i = 0; i < variants.length; i++)
                      i.toString(): variants[i],
                  },
                )
              : null,
        ),
      );
      emit(
        state.copyWith(
          status: StateIsMessaging(
            BeaconCreatedMessage(
              onPressed: () => GetIt.I<ScreenCubit>().showBeacon(beacon.id),
            ),
          ),
        ),
      );
      emit(state.copyWith(status: StateIsNavigating.back));
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
