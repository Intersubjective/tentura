import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/oidc_identity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';

import '_use_case_base.dart';

@Injectable(order: 2)
final class OidcCase extends UseCaseBase {
  OidcCase(
    this._userRepository,
    this._invitationCase, {
    required super.env,
    required super.logger,
  });

  final UserRepositoryPort _userRepository;
  final InvitationCase _invitationCase;

  /// Resolve or create the account for a verified Google OIDC identity.
  Future<String> completeGoogle(
    OidcIdentity identity, {
    String? inviteId,
  }) async {
    final existing = await _findByGoogleSub(identity.sub);
    if (existing != null) {
      if (inviteId != null && inviteId.isNotEmpty) {
        await _invitationCase.acceptAsExisting(
          code: inviteId,
          userId: existing.id,
        );
      }
      return existing.id;
    }

    if (inviteId == null || inviteId.isEmpty) {
      if (env.isNeedInvite) {
        throw const OidcInviteRequiredException();
      }
      final user = await _userRepository.createWithCredential(
        type: CredentialType.oidcGoogle,
        identifier: identity.sub,
        displayName: identity.displayName,
        publicData: identity.publicData,
      );
      return user.id;
    }

    final user = await _userRepository.createInvitedWithCredential(
      invitationId: inviteId,
      type: CredentialType.oidcGoogle,
      identifier: identity.sub,
      displayName: identity.displayName,
      publicData: identity.publicData,
    );
    return user.id;
  }

  Future<UserEntity?> _findByGoogleSub(String sub) async {
    try {
      return await _userRepository.getByCredential(
        type: CredentialType.oidcGoogle.wire,
        identifier: sub,
      );
    } catch (_) {
      return null;
    }
  }
}
