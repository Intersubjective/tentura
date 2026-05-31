import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';

/// Persistence port for users (implemented by the server user repository).
abstract class UserRepositoryPort {
  Future<UserEntity> create({
    required String publicKey,
    required String displayName,
    String? handle,
  });

  Future<UserEntity> createInvited({
    required String invitationId,
    required String publicKey,
    required String displayName,
    String? handle,
  });

  /// Seedless account with a single non-device credential (e.g. OIDC).
  Future<UserEntity> createWithCredential({
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
  });

  /// Invite acceptance for seedless credential accounts (no `ed25519_device`).
  Future<UserEntity> createInvitedWithCredential({
    required String invitationId,
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
  });

  Future<UserEntity> getById(String id);

  Future<UserEntity> getByPublicKey(String publicKey);

  /// Resolve the account that owns the credential identified by
  /// `(type, identifier)` (the multi-credential auth lookup path).
  Future<UserEntity> getByCredential({
    required String type,
    required String identifier,
  });

  /// All credentials linked to [accountId] (Settings `Sign-in methods` list).
  Future<List<AccountCredentialEntity>> listCredentials({
    required String accountId,
  });

  /// Link a credential to [accountId]. Throws `CredentialConflictException`
  /// when the `(type, identifier)` pair is already linked (on this or another
  /// account) — conflict policy never auto-merges.
  Future<AccountCredentialEntity> addCredential({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
  });

  /// Remove credential [credentialId] from [accountId]. Throws
  /// `LastCredentialException` if it is the account's only credential, and
  /// `IdNotFoundException` if no such credential belongs to the account.
  Future<void> removeCredential({
    required String accountId,
    required String credentialId,
  });

  Future<void> update({
    required String id,
    String? displayName,
    String? description,
    String? imageId,
    bool dropImage = false,
    bool setHandle = false,
    String? handle,
  });

  Future<void> deleteById({required String id});

  Future<bool> bindMutual({
    required String invitationId,
    required String userId,
  });
}
