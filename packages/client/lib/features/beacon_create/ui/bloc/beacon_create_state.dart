import 'package:tentura/consts.dart';
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
    String? iconCode,
    int? iconBackground,

    /// Server draft beacon id when editing a draft; null otherwise.
    String? draftId,

    /// Server beacon id when editing a published (open) beacon; null otherwise.
    String? editId,
    String? lineageParentBeaconId,
    @Default({}) Set<String> initialServerImageIds,
    @Default(false) bool canTryToPublish,
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
}
