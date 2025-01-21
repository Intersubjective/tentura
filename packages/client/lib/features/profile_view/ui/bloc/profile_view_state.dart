import 'package:tentura/domain/entity/beacon.dart';
import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'profile_view_state.freezed.dart';

@freezed
class ProfileViewState extends StateBase with _$ProfileViewState {
  const factory ProfileViewState({
    @Default([]) List<Beacon> beacons,
    @Default(Profile()) Profile profile,
    @Default(false) bool hasReachedMax,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _ProfileViewState;

  const ProfileViewState._();

  bool get hasNotReachedMax => !hasReachedMax;
}
