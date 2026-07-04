import 'dart:async' show unawaited;
import 'package:tentura_root/domain/entity/beacon_status.dart';

import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/data/repository/image_repository.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/exception/user_input_exception.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';

import 'package:tentura/domain/entity/beacon_identity_catalog.dart';
import 'package:tentura/features/beacon/data/repository/beacon_repository.dart';
import 'package:tentura/ui/utils/string_input_validator.dart'
    show StringInputValidator;

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
    UiEffectPort? effects,
  }) : _beaconRepository = beaconRepository ?? GetIt.I<BeaconRepository>(),
       _imageRepository = imageRepository ?? GetIt.I<ImageRepository>(),
       _effects = effects ?? GetIt.I<UiEffectPort>(),
       super(
         BeaconCreateState(
           status:
               (draftBeaconIdToLoad != null &&
                       draftBeaconIdToLoad.isNotEmpty) ||
                   (editBeaconIdToLoad != null && editBeaconIdToLoad.isNotEmpty)
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

  final UiEffectPort _effects;

  void _emitSnackError(Object error) {
    _effects.emit(ShowError(error));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  void _emitSnackMessage(LocalizableMessage message) {
    _effects.emit(ShowMessage(message));
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  void _emitNavigateBack() {
    _effects.emit(const NavigateBack());
    if (!isClosed) {
      emit(state.copyWith(status: const StateIsSuccess()));
    }
  }

  static const kNeedSummaryHardMax = BeaconCreateState.needSummaryHardMax;

  static const kNeedSummaryPublishMin = BeaconCreateState.needSummaryPublishMin;

  static const kSuccessCriteriaHardMax =
      BeaconCreateState.successCriteriaHardMax;

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
      if (beacon.status != BeaconStatus.draft) {
        _emitSnackError(Exception('Request is not a draft'));
        return;
      }

      final coords = beacon.coordinates;
      final coordinates = coords != null && coords.isNotEmpty ? coords : null;
      final locationLabel = coordinates != null
          ? beacon.addressLabel ?? ''
          : '';

      emit(
        state.copyWith(
          draftId: beacon.id,
          lineageParentBeaconId: beacon.lineageParentBeaconId,
          title: beacon.title,
          needSummary: beacon.needSummary ?? '',
          successCriteria: beacon.successCriteria ?? '',
          description: beacon.description,
          tags: beacon.tags,
          needs: beacon.needs,
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
      _emitSnackError(e);
    }
  }

  Future<void> loadEdit(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final beacon = await _beaconRepository.fetchBeaconById(id);
      if (beacon.status != BeaconStatus.open) {
        _emitSnackError(Exception('Only open requests can be edited'));
        return;
      }

      final coords = beacon.coordinates;
      final coordinates = coords != null && coords.isNotEmpty ? coords : null;
      final locationLabel = coordinates != null
          ? beacon.addressLabel ?? ''
          : '';

      emit(
        state.copyWith(
          editId: beacon.id,
          title: beacon.title,
          needSummary: beacon.needSummary ?? '',
          successCriteria: beacon.successCriteria ?? '',
          description: beacon.description,
          tags: beacon.tags,
          needs: beacon.needs,
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
      _emitSnackError(e);
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

  void setNeeds(Set<String> value) =>
      emit(state.copyWith(needs: Set<String>.from(value)));

  void removeNeed(String slug) {
    if (!state.needs.contains(slug)) {
      return;
    }
    final next = Set<String>.from(state.needs)..remove(slug);
    emit(state.copyWith(needs: next));
  }

  ///
  ///
  void setDateRange({DateTime? startAt, DateTime? endAt}) => emit(
    state.copyWith(
      startAt: startAt,
      endAt: endAt,
    ),
  );

  /// Deadline timing: only [endAt] is set ("needs to happen by"); `startAt` is
  /// cleared so the card derives a deadline (vs an event) from nullability.
  void setDeadline(DateTime? endAt) => emit(
    state.copyWith(startAt: null, endAt: endAt),
  );

  /// Event timing: [startAt] is the moment it happens; [endAt] (optional) makes
  /// it a window. The card derives an event from a non-null [startAt].
  void setEventDates({required DateTime startAt, DateTime? endAt}) => emit(
    state.copyWith(startAt: startAt, endAt: endAt),
  );

  /// Clears all schedule dates (flexible / no date).
  void clearTiming() => emit(
    state.copyWith(startAt: null, endAt: null),
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
      iconBackground:
          state.iconBackground ?? kBeaconIdentityPalette.first.backgroundArgb,
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
      _emitSnackError(e);
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

  /// Same bounds as [StringInputValidator] title/description checks on the form.
  bool _stateMeetsBaseFormRequirements() => state.meetsPublishFormRequirements;

  ///
  ///
  void validate([bool formValid = false]) {
    final canPublish = formValid || _stateMeetsBaseFormRequirements();
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
      needs: state.needs,
      title: _draftSafeTitle(state.title),
      coordinates: state.coordinates,
      addressLabel: state.location.trim().isEmpty
          ? null
          : state.location.trim(),
      description: state.description.trim(),
      needSummary: ns.isEmpty ? null : ns,
      successCriteria: sc.isEmpty ? null : sc,
      startAt: state.startAt,
      endAt: state.endAt,
      images: state.images,
      iconCode: hasIcon ? iconCode : null,
      iconBackground: hasIcon ? state.iconBackground : null,
    );
  }

  ///
  ///
  Future<void> saveDraft({required String context}) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final now = DateTime.timestamp();
      final beaconPayload = _beaconPayload(context: context, now: now);

      if (state.draftId == null) {
        final created = await _beaconRepository.create(
          beaconPayload,
          draft: true,
        );
        final skipFirst =
            state.images.isNotEmpty && state.images.first.imageBytes != null;
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
            status: const StateIsSuccess(),
          ),
        );
        _emitSnackMessage(const DraftSavedMessage());
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
            status: const StateIsSuccess(),
          ),
        );
        _emitSnackMessage(const DraftSavedMessage());
      }
    } catch (e) {
      _emitSnackError(e);
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
        needs: state.needs,
        title: state.title,
        coordinates: state.coordinates,
        addressLabel: state.location.trim().isEmpty
            ? null
            : state.location.trim(),
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
          status: const StateIsSuccess(),
        ),
      );
      _emitNavigateBack();
    } catch (e) {
      _emitSnackError(e);
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
      _emitSnackError(const BeaconNeedSummaryTooShortException());
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final now = DateTime.timestamp();
      final beaconPayload = _beaconPayload(context: context, now: now);

      if (state.draftId != null) {
        final id = state.draftId!;
        await _syncDraftServerImages(id);
        await _beaconRepository.updateDraft(beaconPayload);
        await _beaconRepository.publishDraft(id);
        emit(state.copyWith(status: const StateIsSuccess()));
        _effects.emit(
          ShowMessage(
            BeaconCreatedMessage(
              onPressed: () => GetIt.I<ScreenCubit>().showBeacon(id),
            ),
          ),
        );
        _emitNavigateBack();
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
            needs: state.needs,
            title: state.title,
            coordinates: state.coordinates,
            addressLabel: state.location.trim().isEmpty
                ? null
                : state.location.trim(),
            description: state.description,
            needSummary: ns.isEmpty ? null : ns,
            successCriteria: sc.isEmpty ? null : sc,
            startAt: state.startAt,
            endAt: state.endAt,
            images: state.images,
            iconCode: hasIcon ? iconCode : null,
            iconBackground: hasIcon ? state.iconBackground : null,
          ),
        );
        emit(state.copyWith(status: const StateIsSuccess()));
        _effects.emit(
          ShowMessage(
            BeaconCreatedMessage(
              onPressed: () => GetIt.I<ScreenCubit>().showBeacon(beacon.id),
            ),
          ),
        );
        _emitNavigateBack();
      }
    } catch (e) {
      _emitSnackError(e);
    }
  }
}
