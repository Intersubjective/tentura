import 'dart:async' show unawaited;

import 'package:get_it/get_it.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/beacon_lifecycle.dart';
import 'package:tentura/domain/entity/polling.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';

import 'package:tentura/domain/entity/beacon_identity_catalog.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/ui/utils/string_input_validator.dart' show StringInputValidator;

import '../message/beacon_create_message.dart';
import 'beacon_create_state.dart';

export 'package:tentura/ui/bloc/state_base.dart';

export 'beacon_create_state.dart';

class BeaconCreateCubit extends Cubit<BeaconCreateState> {
  BeaconCreateCubit({
    ImageRepository? imageRepository,
    BeaconRepository? beaconRepository,
    String? draftBeaconIdToLoad,
    String? editBeaconIdToLoad,
  }) : _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _imageRepository = imageRepository ?? GetIt.I<ImageRepository>(),
       super(
         BeaconCreateState(
           variants: ['', ''],
           variantsKeys: [UniqueKey(), UniqueKey()],
           status:
               (draftBeaconIdToLoad != null && draftBeaconIdToLoad.isNotEmpty) ||
                       (editBeaconIdToLoad != null &&
                           editBeaconIdToLoad.isNotEmpty)
                   ? StateStatus.isLoading
                   : const StateIsSuccess(),
         ),
       ) {
    if (draftBeaconIdToLoad != null && draftBeaconIdToLoad.isNotEmpty) {
      unawaited(Future<void>.microtask(() => loadDraft(draftBeaconIdToLoad)));
    } else if (editBeaconIdToLoad != null && editBeaconIdToLoad.isNotEmpty) {
      unawaited(Future<void>.microtask(() => loadEdit(editBeaconIdToLoad)));
    }
  }

  final BeaconRepository _beaconRepository;

  final ImageRepository _imageRepository;

  static const kNeedSummaryHardMax = 280;

  static const kNeedSummaryPublishMin = 16;

  static const kSuccessCriteriaHardMax = 240;

  static String _draftSafeTitle(String raw) {
    final t = raw.trim();
    if (t.length >= kTitleMinLength) {
      return t;
    }
    return 'Draft';
  }

  Future<void> loadDraft(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final beacon = await _beaconRepository.fetchBeaconById(id);
      if (beacon.lifecycle != BeaconLifecycle.draft) {
        emit(
          state.copyWith(
            status: StateHasError(
              Exception('Beacon is not a draft'),
            ),
          ),
        );
        return;
      }

      final p = beacon.polling;
      var variants = <String>['', ''];
      var variantKeys = <Key>[UniqueKey(), UniqueKey()];
      var question = '';
      if (p != null && p.hasVariants) {
        question = p.question;
        final sorted = p.variants.entries.toList()
          ..sort((a, b) {
            final ai = int.tryParse(a.key) ?? 0;
            final bi = int.tryParse(b.key) ?? 0;
            return ai.compareTo(bi);
          });
        variants = sorted.map((e) => e.value).toList();
        if (variants.length < 2) {
          variants = [...variants, ...List.filled(2 - variants.length, '')];
        }
        variantKeys = List.generate(variants.length, (_) => UniqueKey());
      }

      final coords = beacon.coordinates;
      final coordinates =
          coords != null && coords.isNotEmpty ? coords : null;
      final locationLabel =
          coordinates != null ? coordinates.toString() : '';

      emit(
        state.copyWith(
          draftId: beacon.id,
          title: beacon.title,
          needSummary: beacon.needSummary ?? '',
          successCriteria: beacon.successCriteria ?? '',
          description: beacon.description,
          tags: beacon.tags,
          coordinates: coordinates,
          location: locationLabel,
          startAt: beacon.startAt,
          endAt: beacon.endAt,
          iconCode: beacon.iconCode,
          iconBackground: beacon.iconBackground,
          question: question,
          variants: variants,
          variantsKeys: variantKeys,
          images: [...beacon.images],
          initialServerImageIds: {
            for (final img in beacon.images)
              if (img.id.isNotEmpty) img.id,
          },
          status: StateStatus.isSuccess,
        ),
      );
      validate();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> loadEdit(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final beacon = await _beaconRepository.fetchBeaconById(id);
      if (beacon.lifecycle != BeaconLifecycle.open) {
        emit(
          state.copyWith(
            status: StateHasError(
              Exception('Only open beacons can be edited'),
            ),
          ),
        );
        return;
      }

      final coords = beacon.coordinates;
      final coordinates =
          coords != null && coords.isNotEmpty ? coords : null;
      final locationLabel =
          coordinates != null ? coordinates.toString() : '';

      emit(
        state.copyWith(
          editId: beacon.id,
          title: beacon.title,
          needSummary: beacon.needSummary ?? '',
          successCriteria: beacon.successCriteria ?? '',
          description: beacon.description,
          tags: beacon.tags,
          coordinates: coordinates,
          location: locationLabel,
          startAt: beacon.startAt,
          endAt: beacon.endAt,
          iconCode: beacon.iconCode,
          iconBackground: beacon.iconBackground,
          images: [...beacon.images],
          initialServerImageIds: {
            for (final img in beacon.images)
              if (img.id.isNotEmpty) img.id,
          },
          status: StateStatus.isSuccess,
        ),
      );
      validate();
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  ///
  void setTitle(String value) => emit(state.copyWith(title: value));

  ///
  ///
  void setDescription(String value) => emit(state.copyWith(description: value));

  void setNeedSummary(String value) => emit(state.copyWith(needSummary: value));

  void setSuccessCriteria(String value) =>
      emit(state.copyWith(successCriteria: value));

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

  void setIconCode(String value) => emit(
        state.copyWith(
          iconCode: value,
          iconBackground: state.iconBackground ??
              kBeaconIdentityPalette.first.backgroundArgb,
        ),
      );

  void setIconBackground(int? value) =>
      emit(state.copyWith(iconBackground: value));

  void clearBeaconIdentity() =>
      emit(state.copyWith(iconCode: null, iconBackground: null));

  ///
  ///
  static const kMaxImagesPerBeacon = 10;

  Future<void> pickImages() async {
    try {
      final picked = await _imageRepository.pickMultipleImages();
      if (picked.isNotEmpty) {
        final combined = <ImageEntity>[
          ...state.images,
          ...picked.map((e) => e.toImageEntity()),
        ];
        if (combined.length > kMaxImagesPerBeacon) {
          combined.length = kMaxImagesPerBeacon;
        }
        emit(state.copyWith(images: combined));
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  ///
  void removeImage(int index) {
    final images = [...state.images]..removeAt(index);
    emit(state.copyWith(images: images));
  }

  ///
  ///
  void clearAllImages() => emit(state.copyWith(images: []));

  ///
  ///
  void reorderImages(int oldIndex, int newIndex) {
    final images = [...state.images];
    final item = images.removeAt(oldIndex);
    final adjustedIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    images.insert(adjustedIndex, item);
    emit(state.copyWith(images: images));
  }

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

  /// Same bounds as [StringInputValidator] title/description checks on the form.
  bool _stateMeetsBaseFormRequirements() {
    final t = state.title;
    if (t.length < kTitleMinLength || t.length > kTitleMaxLength) {
      return false;
    }
    if (state.description.length > kDescriptionMaxLength) {
      return false;
    }
    if (state.needSummary.length > kNeedSummaryHardMax) {
      return false;
    }
    if (state.successCriteria.length > kSuccessCriteriaHardMax) {
      return false;
    }
    return true;
  }

  ///
  ///
  void validate([bool formValid = false]) {
    var canPublish = formValid || _stateMeetsBaseFormRequirements();

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

  Future<void> _syncDraftServerImages(
    String beaconId, {
    /// When true, skip index 0 (already sent as multipart on `beaconCreate`).
    bool skipFirstMultipart = false,
  }) async {
    final currentIds = state.images
        .map((e) => e.id)
        .where((e) => e.isNotEmpty)
        .toSet();
    for (final id in state.initialServerImageIds) {
      if (!currentIds.contains(id)) {
        await _beaconRepository.removeImage(beaconId: beaconId, imageId: id);
      }
    }
    for (var i = 0; i < state.images.length; i++) {
      final img = state.images[i];
      if (img.imageBytes != null) {
        if (skipFirstMultipart && i == 0) {
          continue;
        }
        await _beaconRepository.addImage(beaconId: beaconId, image: img);
      }
    }
  }

  Beacon _beaconPayload({
    required String context,
    required DateTime now,
    required bool hasPolling,
    required List<String> variants,
  }) {
    final iconCode = state.iconCode?.trim();
    final hasIcon = iconCode != null && iconCode.isNotEmpty;
    final id = state.draftId ?? '';
    final ns = state.needSummary.trim();
    final sc = state.successCriteria.trim();
    return Beacon(
      id: id,
      createdAt: now,
      updatedAt: now,
      context: context,
      tags: state.tags,
      title: _draftSafeTitle(state.title),
      coordinates: state.coordinates,
      description: state.description,
      needSummary: ns.isEmpty ? null : ns,
      successCriteria: sc.isEmpty ? null : sc,
      startAt: state.startAt,
      endAt: state.endAt,
      images: state.images,
      iconCode: hasIcon ? iconCode : null,
      iconBackground: hasIcon ? state.iconBackground : null,
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
    );
  }

  ///
  ///
  Future<void> saveDraft({required String context}) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final now = DateTime.timestamp();
      final variants = state.variants.where((e) => e.isNotEmpty).toList();
      final hasPolling = state.question.isNotEmpty && variants.isNotEmpty;
      final beaconPayload = _beaconPayload(
        context: context,
        now: now,
        hasPolling: hasPolling,
        variants: variants,
      );

      if (state.draftId == null) {
        final created = await _beaconRepository.create(
          beaconPayload,
          draft: true,
        );
        final skipFirst = state.images.isNotEmpty &&
            state.images.first.imageBytes != null;
        await _syncDraftServerImages(
          created.id,
          skipFirstMultipart: skipFirst,
        );
        final refreshed = await _beaconRepository.fetchBeaconById(created.id);
        emit(
          state.copyWith(
            draftId: refreshed.id,
            images: [...refreshed.images],
            initialServerImageIds: {
              for (final img in refreshed.images)
                if (img.id.isNotEmpty) img.id,
            },
            status: StateIsMessaging(const DraftSavedMessage()),
          ),
        );
        emit(state.copyWith(status: const StateIsSuccess()));
      } else {
        final id = state.draftId!;
        await _syncDraftServerImages(id);
        final updated = await _beaconRepository.updateDraft(beaconPayload);
        emit(
          state.copyWith(
            images: [...updated.images],
            initialServerImageIds: {
              for (final img in updated.images)
                if (img.id.isNotEmpty) img.id,
            },
            status: StateIsMessaging(const DraftSavedMessage()),
          ),
        );
        emit(state.copyWith(status: const StateIsSuccess()));
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  ///
  /// Persists edits to an open (published) beacon.
  Future<void> saveEdit({required String context}) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final id = state.editId!;
      final now = DateTime.timestamp();
      final iconCode = state.iconCode?.trim();
      final hasIcon = iconCode != null && iconCode.isNotEmpty;
      final ns = state.needSummary.trim();
      final sc = state.successCriteria.trim();
      final beaconPayload = Beacon(
        id: id,
        createdAt: now,
        updatedAt: now,
        context: context,
        tags: state.tags,
        title: state.title,
        coordinates: state.coordinates,
        description: state.description,
        needSummary: ns.isEmpty ? null : ns,
        successCriteria: sc.isEmpty ? null : sc,
        startAt: state.startAt,
        endAt: state.endAt,
        images: state.images,
        iconCode: hasIcon ? iconCode : null,
        iconBackground: hasIcon ? state.iconBackground : null,
      );

      await _syncEditServerImages(id);
      final updated = await _beaconRepository.update(beaconPayload);
      emit(
        state.copyWith(
          images: [...updated.images],
          initialServerImageIds: {
            for (final img in updated.images)
              if (img.id.isNotEmpty) img.id,
          },
          status: StateIsNavigating.back,
        ),
      );
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }

  Future<void> _syncEditServerImages(String beaconId) async {
    final currentIds = state.images
        .map((e) => e.id)
        .where((e) => e.isNotEmpty)
        .toSet();
    for (final id in state.initialServerImageIds) {
      if (!currentIds.contains(id)) {
        await _beaconRepository.removeImage(beaconId: beaconId, imageId: id);
      }
    }
    for (final img in state.images) {
      if (img.imageBytes != null) {
        await _beaconRepository.addImage(beaconId: beaconId, image: img);
      }
    }
  }

  ///
  ///
  Future<void> publish({required String context}) async {
    if (state.needSummary.trim().length < kNeedSummaryPublishMin) {
      return emit(
        state.copyWith(
          status: StateHasError(const BeaconNeedSummaryTooShortException()),
        ),
      );
    }
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
      final beaconPayload = _beaconPayload(
        context: context,
        now: now,
        hasPolling: hasPolling,
        variants: variants,
      );

      if (state.draftId != null) {
        final id = state.draftId!;
        await _syncDraftServerImages(id);
        await _beaconRepository.updateDraft(beaconPayload);
        await _beaconRepository.publishDraft(id);
        emit(
          state.copyWith(
            status: StateIsMessaging(
              BeaconCreatedMessage(
                onPressed: () => GetIt.I<ScreenCubit>().showBeacon(id),
              ),
            ),
          ),
        );
        emit(state.copyWith(status: StateIsNavigating.back));
      } else {
        final iconCode = state.iconCode?.trim();
        final hasIcon = iconCode != null && iconCode.isNotEmpty;
        final ns = state.needSummary.trim();
        final sc = state.successCriteria.trim();
        final beacon = await _beaconRepository.create(
          Beacon(
            createdAt: now,
            updatedAt: now,
            context: context,
            tags: state.tags,
            title: state.title,
            coordinates: state.coordinates,
            description: state.description,
            needSummary: ns.isEmpty ? null : ns,
            successCriteria: sc.isEmpty ? null : sc,
            startAt: state.startAt,
            endAt: state.endAt,
            images: state.images,
            iconCode: hasIcon ? iconCode : null,
            iconBackground: hasIcon ? state.iconBackground : null,
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
      }
    } catch (e) {
      emit(state.copyWith(status: StateHasError(e)));
    }
  }
}
