import 'package:tentura/domain/entity/invitation_entity.dart';
import 'package:tentura/ui/bloc/state_base.dart';

part 'invitation_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class InvitationState extends StateBase with _$InvitationState {
  const factory InvitationState({
    @Default([]) List<InvitationEntity> pendingInvitations,
    @Default([]) List<InvitationEntity> acceptedInvitations,
    @Default(false) bool pendingHasReachedMax,
    @Default(false) bool acceptedHasReachedMax,

    /// True total of pending invitations (drives the tab badge) —
    /// independent of how many pending rows have been paginated in so far.
    @Default(0) int pendingCount,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _InvitationState;

  const InvitationState._();
}
