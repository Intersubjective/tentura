import 'package:tentura/domain/entity/opinion.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'profile_view_state.freezed.dart';

@freezed
abstract class ProfileViewState extends StateBase with _$ProfileViewState {
  const factory ProfileViewState({
    @Default(Profile()) Profile profile,
    @Default('') String focusOpinionId,
    @Default(false) bool hasReachedMax,
    @Default([]) List<Opinion> comments,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ProfileViewState;

  const ProfileViewState._();

  bool get hasNotReachedMax => !hasReachedMax;

  bool get hasFocusedOpinion => focusOpinionId.isNotEmpty;
  bool get hasNoFocusedOpinion => focusOpinionId.isEmpty;
}
