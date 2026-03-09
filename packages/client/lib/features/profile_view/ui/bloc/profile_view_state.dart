import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'profile_view_state.freezed.dart';

@freezed
abstract class ProfileViewState extends StateBase with _$ProfileViewState {
  const factory ProfileViewState({
    @Default(Profile()) Profile profile,
    @Default('') String focusOpinionId,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ProfileViewState;

  const ProfileViewState._();
}
