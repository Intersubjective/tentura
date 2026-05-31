import 'package:tentura/ui/bloc/state_base.dart';

import '../../domain/entity/credential_entity.dart';

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
}
