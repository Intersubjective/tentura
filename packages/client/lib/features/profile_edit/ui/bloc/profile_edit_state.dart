import 'package:tentura/consts.dart';
import 'package:tentura/domain/entity/image_entity.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'profile_edit_state.freezed.dart';

@freezed
abstract class ProfileEditState extends StateBase with _$ProfileEditState {
  const factory ProfileEditState({
    required Profile original,
    required String displayName,
    required String handle,
    required String description,
    @Default(false) bool canDropImage,
    @Default(false) bool willDropImage,
    @Default(StateIsSuccess()) StateStatus status,
    ImageEntity? image,
  }) = _ProfileEditState;

  const ProfileEditState._();

  bool get hasImage => image != null;

  bool get hasNoImage => image == null;

  bool get hasChanges =>
      hasImage ||
      willDropImage ||
      original.displayName != displayName ||
      original.handle != handle ||
      original.description != description;

  /// Whether [displayName] is acceptable to persist (trimmed length rules).
  bool get canSave {
    final trimmed = displayName.trim();
    return trimmed.length >= kTitleMinLength &&
        displayName.length <= kTitleMaxLength;
  }
}
