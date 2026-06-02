import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';
import 'package:tentura_server/domain/use_case/invitation_case.dart';

import '_use_case_base.dart';

/// Shared resolve-or-create-with-invite path for seedless credentials (Google, email).
@Injectable(order: 2)
final class CredentialAuthCase extends UseCaseBase {
  CredentialAuthCase(
    this._userRepository,
    this._invitationCase, {
    required super.env,
    required super.logger,
  });

  final UserRepositoryPort _userRepository;
  final InvitationCase _invitationCase;

  /// Returns account id after login or signup.
  Future<String> resolveOrCreate({
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? inviteId,
    Map<String, Object?>? publicData,
  }) async {
    final existing = await _findByCredential(type, identifier);
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
        type: type,
        identifier: identifier,
        displayName: displayName,
        publicData: publicData,
      );
      return user.id;
    }

    final user = await _userRepository.createInvitedWithCredential(
      invitationId: inviteId,
      type: type,
      identifier: identifier,
      displayName: displayName,
      publicData: publicData,
    );
    return user.id;
  }

  Future<UserEntity?> _findByCredential(
    CredentialType type,
    String identifier,
  ) async {
    try {
      return await _userRepository.getByCredential(
        type: type.wire,
        identifier: identifier,
      );
    } catch (_) {
      return null;
    }
  }
}
