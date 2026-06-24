import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
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
    List<AssertedContact> contacts = const [],
  });

  /// Invite acceptance for seedless credential accounts (no `ed25519_device`).
  Future<UserEntity> createInvitedWithCredential({
    required String invitationId,
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
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
  /// when the `(type, identifier)` pair is already linked to a **different**
  /// account — verified-contact unification may still auto-link by policy.
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

  /// Atomically link [type]/[identifier] and authoritative [contacts] to
  /// [accountId]. When the credential is already linked to [accountId], treats
  /// the call as idempotent. When linked elsewhere, returns that account id.
  Future<String> linkCredentialWithContacts({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  });

  /// Settings-linking primitive (NOT login/signup): strictly attach a credential
  /// to [accountId]. Unlike [linkCredentialWithContacts] it never returns another
  /// account and never auto-merges:
  /// - already linked to [accountId] → idempotent, returns the existing row;
  /// - `(type, identifier)` owned by a different account →
  ///   `CredentialConflictException`;
  /// - an authoritative contact owned by a different account →
  ///   `ContactConflictException`.
  Future<AccountCredentialEntity> linkCredentialToAccountStrict({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  });

  /// Internal id of the `(type, identifier)` credential, or null when absent.
  /// Used to attribute `account_session.credential_id` after login/link.
  Future<String?> findCredentialId({
    required CredentialType type,
    required String identifier,
  });

  /// Soft upsert for existing-credential login: attach unclaimed or same-account
  /// contacts; skip contacts owned by another account without throwing.
  Future<void> addVerifiedContacts({
    required String accountId,
    required CredentialType source,
    List<AssertedContact> contacts = const [],
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
    bool bindFriendship = true,
  });
}
