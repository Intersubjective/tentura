import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/capability/tag_projection.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'profile_view_state.freezed.dart';

@freezed
abstract class ProfileViewState extends StateBase with _$ProfileViewState {
  const factory ProfileViewState({
    @Default(Profile()) Profile profile,
    @Default(StateIsSuccess()) StateStatus status,
    @Default(PersonCapabilityCues.empty) PersonCapabilityCues cues,
    @Default([]) List<TagProjection> subjectiveTags,
    Object? loadError,
    Profile? blockedProfile,
  }) = _ProfileViewState;

  const ProfileViewState._();

  bool get hasError => loadError != null;

  bool get isBlockedFallback => blockedProfile != null;
}
