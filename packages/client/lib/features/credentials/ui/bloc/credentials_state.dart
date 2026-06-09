import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/credential_entity.dart';
import '../../domain/entity/credential_link_policy.dart';
import '../../domain/entity/credential_types.dart';

export 'package:tentura/ui/bloc/state_base.dart';

part 'credentials_state.freezed.dart';

@Freezed(makeCollectionsUnmodifiable: false)
abstract class CredentialsState extends StateBase with _$CredentialsState {
  const factory CredentialsState({
    required DateTime updatedAt,
    @Default([]) List<CredentialEntity> credentials,
    @Default(StateIsSuccess()) StateStatus status,
  }) = _CredentialsState;

  const CredentialsState._();

  bool get canAddGoogle =>
      CredentialLinkPolicy.canLink(CredentialTypes.oidcGoogle, credentials);

  bool get canAddEmail =>
      CredentialLinkPolicy.canLink(CredentialTypes.emailOtp, credentials);

  bool get canAddRecoverySeed =>
      CredentialLinkPolicy.canLink(CredentialTypes.ed25519Device, credentials);

  bool get showAddSection =>
      canAddGoogle || canAddEmail || canAddRecoverySeed;
}
