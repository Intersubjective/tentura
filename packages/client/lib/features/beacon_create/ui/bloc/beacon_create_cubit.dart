import 'dart:async' show unawaited;

import 'package:get_it/get_it.dart';
import 'package:tentura_root/domain/capability/capability_slugs.dart';
import 'package:tentura_root/domain/entity/beacon_cover_source.dart';
import 'package:tentura_root/domain/entity/beacon_status.dart';
import 'package:tentura_root/domain/entity/localizable.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/beacon_schedule.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/port/beacon_image_port.dart';
import 'package:tentura/domain/use_case/beacon_create_case.dart';
import 'package:tentura/features/forward/ui/bloc/forward_cubit.dart';
import 'package:tentura/ui/bloc/screen_cubit.dart';
import 'package:tentura/ui/effect/ui_effect.dart';
import 'package:tentura/ui/effect/ui_effect_port.dart';
import 'package:tentura/ui/utils/string_input_validator.dart'
    show StringInputValidator;

import '../message/beacon_create_message.dart';
import 'beacon_create_state.dart';

export 'package:tentura/ui/bloc/state_base.dart';

export 'beacon_create_state.dart';

class BeaconCreateCubit extends Cubit<BeaconCreateState> {
  BeaconCreateCubit({
    BeaconCreateCase? beaconCreateCase,
    String? draftBeaconIdToLoad,
    String? editBeaconIdToLoad,
    UiEffectPort? effects,
  }) : _case = beaconCreateCase ?? GetIt.I<BeaconCreateCase>(),
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

  final BeaconCreateCase _case;

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
      final beacon = await _case.fetchById(id);
      if (beacon.status != BeaconStatus.draft) {
        _emitSnackError(Exception('Request is not a draft'));
        return;
      }
      emit(_loadedState(beacon).copyWith(draftId: beacon.id));
      validate();
    } catch (e) {
      _emitSnackError(e);
    }
  }

  Future<void> loadEdit(String id) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final beacon = await _case.fetchById(id);
      if (beacon.status != BeaconStatus.open) {
        _emitSnackError(Exception('Only open requests can be edited'));
        return;
      }
      emit(
        _loadedState(beacon).copyWith(
          editId: beacon.id,
          cachedDeadlineAt: beacon.startAt == null ? beacon.endAt : null,
          cachedEventStartAt: beacon.startAt,
          cachedEventEndAt: beacon.startAt != null ? beacon.endAt : null,
        ),
      );
      validate();
    } catch (e) {
      _emitSnackError(e);
    }
  }

  BeaconCreateState _loadedState(Beacon beacon) {
    final coords = beacon.coordinates;
    final coordinates = coords != null && coords.isNotEmpty ? coords : null;
    return state.copyWith(
      lineageParentBeaconId: beacon.lineageParentBeaconId,
      title: beacon.title,
      description: beacon.description,
      tags: beacon.tags,
      needs: beacon.needs,
      coordinates: coordinates,
      location: coordinates != null ? beacon.addressLabel ?? '' : '',
      startAt: beacon.startAt,
      endAt: beacon.endAt,
      primaryNeedSlug: beacon.primaryNeedSlug,
      coverKey: beacon.coverImage?.key,
      coverSource: beacon.coverSource,
      coverThumb: beacon.coverThumb,
      images: [...beacon.images],
      initialServerImageIds: {
        for (final img in beacon.images)
          if (img.id.isNotEmpty) img.id,
      },
      status: StateStatus.isSuccess,
    );
  }

  BeaconCreateState _applyServerMedia(
    BeaconCreateState from,
    Beacon beacon,
    List<ImageEntity> published, {
    ImageEntity? coverThumb,
  }) => from.copyWith(
    images: published,
    coverKey: beacon.coverImage?.key,
    coverSource: beacon.coverSource,
    coverThumb: coverThumb ?? beacon.coverThumb,
    initialServerImageIds: {
      for (final img in published)
        if (img.id.isNotEmpty) img.id,
    },
    status: const StateIsSuccess(),
  );

  ///
  ///
  void setTitle(String value) => emit(state.copyWith(title: value));

  ///
  ///
  void setDescription(String value) => emit(state.copyWith(description: value));

  void setNeeds(Set<String> value) {
    final needs = Set<String>.from(value);
    emit(
      state.copyWith(
        needs: needs,
        primaryNeedSlug: _promotedPrimary(needs, state.primaryNeedSlug),
      ),
    );
  }

  void removeNeed(String slug) {
    if (!state.needs.contains(slug)) {
      return;
    }
    final next = Set<String>.from(state.needs)..remove(slug);
    emit(
      state.copyWith(
        needs: next,
        primaryNeedSlug: _promotedPrimary(next, state.primaryNeedSlug),
      ),
    );
  }

  /// D-1/N3: keep a still-valid primary, otherwise promote the canonical-first
  /// remaining capability. Empty needs means no primary.
  static String? _promotedPrimary(Set<String> needs, String? current) {
    if (needs.isEmpty) return null;
    if (current != null && needs.contains(current)) return current;
    return canonicalFirstCapabilitySlug(needs);
  }

  ///
  ///
  void setDateRange({DateTime? startAt, DateTime? endAt}) => emit(
    state.copyWith(
      startAt: startAt,
      endAt: endAt,
      cachedEventStartAt: startAt ?? state.cachedEventStartAt,
      cachedEventEndAt: startAt != null ? endAt : state.cachedEventEndAt,
      cachedDeadlineAt: startAt == null && endAt != null
          ? endAt
          : state.cachedDeadlineAt,
    ),
  );

  /// Deadline timing: only [endAt] is set ("needs to happen by"); `startAt` is
  /// cleared so the card derives a deadline (vs an event) from nullability.
  void setDeadline(DateTime? endAt) => emit(
    state.copyWith(
      startAt: null,
      endAt: endAt,
      cachedDeadlineAt: endAt ?? state.cachedDeadlineAt,
    ),
  );

  /// Event timing: [startAt] is the moment it happens; [endAt] (optional) makes
  /// it a window. The card derives an event from a non-null [startAt].
  void setEventDates({required DateTime startAt, DateTime? endAt}) => emit(
    state.copyWith(
      startAt: startAt,
      endAt: endAt,
      cachedEventStartAt: startAt,
      cachedEventEndAt: endAt,
    ),
  );

  /// Clears all schedule dates (flexible / no date).
  void clearTiming() => emit(
    state.copyWith(startAt: null, endAt: null),
  );

  /// Switches the declared meaning of schedule dates without destroying the
  /// user's previously entered values while the editor is open.
  void setTimingKind(BeaconScheduleKind kind) {
    final s = state;
    switch (kind) {
      case BeaconScheduleKind.none:
        emit(s.copyWith(startAt: null, endAt: null));
      case BeaconScheduleKind.deadline:
        final fromEventEnd = s.endAt ?? s.cachedEventEndAt;
        final fromEventStart = s.startAt ?? s.cachedEventStartAt;
        final picked = fromEventEnd ?? fromEventStart ?? s.cachedDeadlineAt;
        emit(
          s.copyWith(
            startAt: null,
            endAt: picked,
            cachedDeadlineAt: picked ?? s.cachedDeadlineAt,
          ),
        );
      case BeaconScheduleKind.event:
        final cachedStart = s.cachedEventStartAt;
        if (cachedStart != null) {
          emit(s.copyWith(startAt: cachedStart, endAt: s.cachedEventEndAt));
          return;
        }

        final promote = s.cachedDeadlineAt ?? s.endAt;
        if (promote != null) {
          emit(
            s.copyWith(
              startAt: promote,
              endAt: null,
              cachedEventStartAt: promote,
              cachedEventEndAt: null,
            ),
          );
        } else {
          emit(s.copyWith(startAt: null, endAt: null));
        }
    }
  }

  ///
  ///
  void setLocation(Coordinates? value, String locationName) => emit(
    state.copyWith(
      coordinates: value,
      location: locationName,
    ),
  );

  /// Cover
  ///
  /// Photo preference requires nothing; the resolver falls back on its own.
  void selectPhotoCoverSource() =>
      emit(state.copyWith(coverSource: BeaconCoverSource.photo));

  /// Symbol preference requires a resolvable primary; the stored photo
  /// selection is deliberately kept.
  void selectSymbolCoverSource() {
    if (!state.canSelectSymbolSource) return;
    emit(state.copyWith(coverSource: BeaconCoverSource.symbol));
  }

  /// D-4: only a capability already in [BeaconCreateState.needs] may be primary.
  void setPrimaryNeedSlug(String slug) {
    if (!state.needs.contains(slug)) return;
    emit(
      state.copyWith(
        primaryNeedSlug: slug,
        coverSource: BeaconCoverSource.symbol,
      ),
    );
  }

  void setCoverImageKey(String key) {
    if (state.images.every((image) => image.key != key)) return;
    emit(
      state.copyWith(
        coverKey: key,
        coverSource: BeaconCoverSource.photo,
        coverThumb: null,
      ),
    );
  }

  void clearCoverThumb() => emit(state.copyWith(coverThumb: null));

  ///
  ///
  static const kMaxImagesPerBeacon = 10;

  Future<void> pickImages() => _pickImages(asCover: false);

  /// Picking from the cover block is an explicit cover choice, so the first
  /// newly picked photo takes the selection.
  Future<void> pickCoverPhoto() => _pickImages(asCover: true);

  Future<void> _pickImages({required bool asCover}) async {
    try {
      final picked = await _case.pickImages();
      if (isClosed || picked.isEmpty) return;
      final combined = <ImageEntity>[...state.images, ...picked];
      if (combined.length > kMaxImagesPerBeacon) {
        combined.length = kMaxImagesPerBeacon;
      }
      final requested = picked.first.key;
      final kept = combined.any((image) => image.key == requested);
      final String? cover;
      if (asCover && kept) {
        cover = requested;
      } else if (state.coverImage == null) {
        // First image becomes the cover; a later one never steals it.
        cover = combined.first.key;
      } else {
        cover = state.coverKey;
      }
      final coverChanged = cover != state.coverKey;
      emit(
        state.copyWith(
          images: combined,
          coverKey: cover,
          coverThumb: coverChanged ? null : state.coverThumb,
          coverSource: asCover && kept
              ? BeaconCoverSource.photo
              : state.coverSource,
        ),
      );
    } catch (e) {
      _emitSnackError(e);
    }
  }

  /// Re-crops the selected cover at 1:1 into [coverThumb] only. Cancelling
  /// preserves images, cover key, thumb, and source exactly.
  Future<void> adjustCoverCrop(ImageCropUiPort cropUi) async {
    final image = state.coverImage;
    if (image == null) return;
    try {
      final replacement = await _case.adjustCoverCrop(
        image: image,
        imageUrl: _serverImageUrl(image),
        cropUi: cropUi,
      );
      if (isClosed || replacement == null) return;
      emit(state.copyWith(coverThumb: replacement));
    } catch (e) {
      _emitSnackError(e);
    }
  }

  static String _serverImageUrl(ImageEntity image) =>
      '$kImageServer/$kImagesPath/${image.authorId}/${image.id}.$kImageExt';

  ///
  ///
  void removeImage(int index) {
    final removed = state.images[index];
    final images = [...state.images]..removeAt(index);
    final coverRemoved = state.coverKey == removed.key;
    emit(
      state.copyWith(
        images: images,
        // Deleting the cover selects the first remaining image by list order;
        // deleting the last one clears the key but keeps the preference.
        coverKey: coverRemoved
            ? (images.isEmpty ? null : images.first.key)
            : state.coverKey,
        coverThumb: coverRemoved ? null : state.coverThumb,
      ),
    );
  }

  ///
  ///
  void clearAllImages() => emit(
    state.copyWith(images: [], coverKey: null, coverThumb: null),
  );

  ///
  ///
  void reorderImages(int oldIndex, int newIndex) {
    final images = [...state.images];
    final item = images.removeAt(oldIndex);
    images.insert(newIndex, item);
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

  Beacon _beaconPayload({
    required String context,
    required DateTime now,
    required String id,
    required bool draftSafeTitle,
  }) {
    return Beacon(
      id: id,
      createdAt: now,
      updatedAt: now,
      context: context,
      tags: state.tags,
      needs: state.needs,
      title: draftSafeTitle ? _draftSafeTitle(state.title) : state.title,
      coordinates: state.coordinates,
      addressLabel: state.location.trim().isEmpty
          ? null
          : state.location.trim(),
      description: draftSafeTitle
          ? state.description.trim()
          : state.description,
      startAt: state.startAt,
      endAt: state.endAt,
      images: state.images,
      primaryNeedSlug: state.primaryNeedSlug,
      coverSource: state.coverSource,
    );
  }

  BeaconSaveCommand _command({
    required String context,
    required String id,
    required bool draftSafeTitle,
    bool draft = false,
  }) => BeaconSaveCommand(
    fields: _beaconPayload(
      context: context,
      now: DateTime.timestamp(),
      id: id,
      draftSafeTitle: draftSafeTitle,
    ),
    images: state.images,
    coverKey: state.coverKey,
    coverThumb: state.coverThumb,
    draft: draft,
  );

  /// Keeps the known beacon id and every already-staged image so a retry never
  /// re-creates the request or re-uploads a staged photo.
  void _emitSaveFailure(BeaconSaveFailure failure) {
    if (!isClosed) {
      emit(
        state.copyWith(
          draftId: state.draftId ?? failure.beaconId,
          images: failure.images,
          coverKey: failure.coverKey,
          coverThumb: failure.coverThumb,
        ),
      );
    }
    _emitSnackError(failure.cause);
  }

  ///
  ///
  Future<String?> ensureDraft({
    required String context,
    bool showMessage = true,
  }) async {
    if (state.draftId != null && state.draftId!.isNotEmpty) {
      return state.draftId;
    }
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final result = await _case.create(
        _command(context: context, id: '', draftSafeTitle: true, draft: true),
      );
      emit(
        _applyServerMedia(
          state.copyWith(draftId: result.beacon.id),
          result.beacon,
          result.images,
          coverThumb: result.coverThumb,
        ),
      );
      if (showMessage) {
        _emitSnackMessage(const DraftSavedMessage());
      }
      return result.beacon.id;
    } on BeaconSaveFailure catch (e) {
      _emitSaveFailure(e);
      return null;
    } catch (e) {
      _emitSnackError(e);
      return null;
    }
  }

  ///
  ///
  Future<void> saveDraft({
    required String context,
    bool showMessage = true,
  }) async {
    final existing = state.draftId;
    if (existing == null || existing.isEmpty) {
      await ensureDraft(context: context, showMessage: showMessage);
      return;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final result = await _case.saveDraft(
        _command(context: context, id: existing, draftSafeTitle: true),
      );
      emit(
        _applyServerMedia(
          state,
          result.beacon,
          result.images,
          coverThumb: result.coverThumb,
        ),
      );
      if (showMessage) {
        _emitSnackMessage(const DraftSavedMessage());
      }
    } on BeaconSaveFailure catch (e) {
      _emitSaveFailure(e);
    } catch (e) {
      _emitSnackError(e);
    }
  }

  /// Publish the draft, then forward to recipients selected in [forwardCubit].
  Future<ForwardDeliveryOutcome?> sendRequest({
    required String context,
    required ForwardCubit forwardCubit,
  }) async {
    if (forwardCubit.state.selectedIds.isEmpty) {
      return null;
    }

    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final draftId =
          state.draftId ??
          await ensureDraft(context: context, showMessage: false);
      if (draftId == null || draftId.isEmpty) {
        return null;
      }

      await saveDraft(context: context, showMessage: false);
      await _case.publishDraft(draftId);
      // Embedded forward() skips allowsForward and the host pops after send;
      // a full candidate reload here only stalls the spinner.

      await forwardCubit.forward();
      final outcome = forwardCubit.state.lastDeliveryOutcome;

      emit(state.copyWith(status: const StateIsSuccess()));

      return outcome;
    } on BeaconSaveFailure catch (e) {
      _emitSaveFailure(e);
      return null;
    } catch (e) {
      _emitSnackError(e);
      return null;
    }
  }

  ///
  /// Persists edits to an open (published) beacon.
  Future<void> saveEdit({required String context}) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final result = await _case.saveEdit(
        _command(context: context, id: state.editId!, draftSafeTitle: false),
      );
      emit(
        _applyServerMedia(
          state,
          result.beacon,
          result.images,
          coverThumb: result.coverThumb,
        ),
      );
      _emitNavigateBack();
    } on BeaconSaveFailure catch (e) {
      _emitSaveFailure(e);
    } catch (e) {
      _emitSnackError(e);
    }
  }

  ///
  ///
  Future<void> publish({required String context}) async {
    emit(state.copyWith(status: StateStatus.isLoading));
    try {
      final existing = state.draftId;
      final String id;
      if (existing != null && existing.isNotEmpty) {
        final result = await _case.saveDraft(
          _command(context: context, id: existing, draftSafeTitle: false),
        );
        emit(
          _applyServerMedia(
            state,
            result.beacon,
            result.images,
            coverThumb: result.coverThumb,
          ),
        );
        id = existing;
      } else {
        // Created as a draft so media reconciles before anyone can read it.
        final result = await _case.create(
          _command(
            context: context,
            id: '',
            draftSafeTitle: false,
            draft: true,
          ),
        );
        emit(
          _applyServerMedia(
            state.copyWith(draftId: result.beacon.id),
            result.beacon,
            result.images,
            coverThumb: result.coverThumb,
          ),
        );
        id = result.beacon.id;
      }

      await _case.publishDraft(id);
      emit(state.copyWith(status: const StateIsSuccess()));
      _effects.emit(
        ShowMessage(
          BeaconCreatedMessage(
            onPressed: () => GetIt.I<ScreenCubit>().showBeacon(id),
          ),
        ),
      );
      _emitNavigateBack();
    } on BeaconSaveFailure catch (e) {
      _emitSaveFailure(e);
    } catch (e) {
      _emitSnackError(e);
    }
  }
}
