import 'package:tentura/domain/entity/profile.dart';
import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/invite_preview.dart';

part 'accept_invite_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class AcceptInviteState extends StateBase with _$AcceptInviteState {
  const factory AcceptInviteState({
    @Default(StateIsLoading()) StateStatus status,
    @Default('') String code,
    ({Profile inviter, InvitePreviewBeacon? beacon, bool phantomInvite})?
    pendingInvite,
    String? pendingSignupCode,
  }) = _AcceptInviteState;

  const AcceptInviteState._();

  Profile? get pendingInviter => pendingInvite?.inviter;

  InvitePreviewBeacon? get pendingBeacon => pendingInvite?.beacon;

  bool get needsConfirmation =>
      pendingInvite != null && status is StateIsSuccess;
}
