import 'package:tentura_root/domain/entity/beacon_cover_source.dart';

import 'package:tentura/consts.dart';
import 'package:tentura/domain/capability/capability_tag.dart';
import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/coordinates.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'beacon_create_state.freezed.dart';

/// First missing field that blocks the Publish action on create / draft flows.
enum BeaconPublishBlocker {
  title,
  description,
}

@Freezed(makeCollectionsUnmodifiable: false)
abstract class BeaconCreateState extends StateBase with _$BeaconCreateState {
  const factory BeaconCreateState({
    @Default('') String title,
    @Default('') String description,
    @Default('') String location,
    @Default({}) Set<String> tags,
    @Default({}) Set<String> needs,
    @Default([]) List<ImageEntity> images,
    Coordinates? coordinates,
    DateTime? startAt,
    DateTime? endAt,

    /// Local-only cached timing values so switching timing kind doesn't destroy
    /// the user's inputs while the editor is open.
    DateTime? cachedDeadlineAt,
    DateTime? cachedEventStartAt,
    DateTime? cachedEventEndAt,

    /// Capability slug driving symbol identity; must be a member of [needs].
    String? primaryNeedSlug,

    /// [ImageEntity.key] of the selected cover; null when there are no images.
    String? coverKey,

    /// Cropped card thumb; separate from gallery [images].
    ImageEntity? coverThumb,

    /// Author preference between photo and symbol presentation.
    @Default(BeaconCoverSource.photo) BeaconCoverSource coverSource,

    /// Server draft beacon id when editing a draft; null otherwise.
    String? draftId,

    /// Server beacon id when editing a published (open) beacon; null otherwise.
    String? editId,
    String? lineageParentBeaconId,
    @Default({}) Set<String> initialServerImageIds,
    @Default(false) bool canTryToPublish,

    /// True after [BeaconCreateCubit.makeLive] in this create session.
    @Default(false) bool isLive,

    /// Quiet draft persist (must not use [StateStatus.isLoading]).
    @Default(false) bool isAutosaving,
    DateTime? lastAutosavedAt,

    /// Show title/description errors after blur or Next, not on every keystroke.
    @Default(false) bool showValidationHints,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _BeaconCreateState;

  const BeaconCreateState._();

  bool get isEditMode => editId != null;

  /// First missing field that blocks Publish on create / draft flows.
  BeaconPublishBlocker? get publishBlocker {
    if (isEditMode) {
      return null;
    }
    final t = title.trim();
    if (t.length < kTitleMinLength || t.length > kBeaconTitleMaxLength) {
      return BeaconPublishBlocker.title;
    }
    final d = description.trim();
    if (d.isEmpty || d.length > kBeaconDescriptionMaxLength) {
      return BeaconPublishBlocker.description;
    }
    return null;
  }

  bool get meetsPublishFormRequirements {
    return publishBlocker == null;
  }

  /// Selected cover among [images], matched by [ImageEntity.key].
  ImageEntity? get coverImage {
    final selected = coverKey;
    if (selected == null) return null;
    for (final image in images) {
      if (image.key == selected) return image;
    }
    return null;
  }

  /// Capability behind [primaryNeedSlug] when it is still a member of [needs].
  CapabilityTag? get primaryCapability {
    final slug = primaryNeedSlug;
    if (slug == null || !needs.contains(slug)) return null;
    return CapabilityTag.fromSlug(slug);
  }

  /// Symbol presentation needs a resolvable capability to show anything.
  bool get canSelectSymbolSource => primaryCapability != null;

  /// Draft projection so the form preview goes through
  /// [Beacon.resolveIdentity] instead of re-deciding identity in the UI.
  Beacon get coverPreview => Beacon.empty.copyWith(
    title: title,
    needs: needs,
    images: images,
    primaryNeedSlug: primaryNeedSlug,
    coverImageId: coverKey,
    coverSource: coverSource,
    coverThumb: coverThumb,
  );
}
