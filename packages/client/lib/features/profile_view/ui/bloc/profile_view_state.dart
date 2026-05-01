import 'package:tentura/domain/capability/person_capability_cues.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'profile_view_state.freezed.dart';

@freezed
abstract class ProfileViewState extends StateBase with _$ProfileViewState {
  const factory ProfileViewState({
    @Default(Profile()) Profile profile,
    @Default('') String focusOpinionId,
    @Default(StateIsSuccess()) StateStatus status,
    @Default(PersonCapabilityCues.empty) PersonCapabilityCues cues,
  }) = _ProfileViewState;

  const ProfileViewState._();
}
