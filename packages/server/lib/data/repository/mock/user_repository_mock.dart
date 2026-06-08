import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/entity/account_credential_entity.dart';
import 'package:tentura_server/domain/entity/asserted_contact.dart';
import 'package:tentura_server/domain/entity/user_entity.dart';
import 'package:tentura_server/domain/exception.dart';
import 'package:tentura_server/domain/port/user_repository_port.dart';

import 'data/users.dart';

@Injectable(
  as: UserRepositoryPort,
  env: [Environment.test],
  order: 1,
)
class UserRepositoryMock implements UserRepositoryPort {
  static final storageByPublicKey = <String, UserEntity>{...kUserByPublicKey};

  const UserRepositoryMock();

  @override
  Future<UserEntity> create({
    required String publicKey,
    required String displayName,
    String? handle,
  }) async => storageByPublicKey.containsKey(publicKey)
      ? throw Exception('Key already exists [$publicKey]')
      : storageByPublicKey[publicKey] = UserEntity(
          id: UserEntity.newId,
          publicKey: publicKey,
          displayName: displayName,
          handle: (handle ?? '').trim(),
        );

  @override
  Future<UserEntity> createInvited({
    required String invitationId,
    required String publicKey,
    required String displayName,
    String? handle,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserEntity> createWithCredential({
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserEntity> createInvitedWithCredential({
    required String invitationId,
    required CredentialType type,
    required String identifier,
    required String displayName,
    String? handle,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<UserEntity> getById(String id) async =>
      storageByPublicKey.values.where((e) => e.id == id).firstOrNull ??
      (throw IdNotFoundException(id: id));

  @override
  Future<UserEntity> getByPublicKey(String publicKey) async =>
      storageByPublicKey[publicKey] ??
      (throw IdNotFoundException(id: publicKey));

  @override
  Future<UserEntity> getByCredential({
    required String type,
    required String identifier,
  }) =>
      // Mock stores users by device public key; for the device credential the
      // identifier is that public key.
      getByPublicKey(identifier);

  @override
  Future<List<AccountCredentialEntity>> listCredentials({
    required String accountId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AccountCredentialEntity> addCredential({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> removeCredential({
    required String accountId,
    required String credentialId,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String> linkCredentialWithContacts({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<AccountCredentialEntity> linkCredentialToAccountStrict({
    required String accountId,
    required CredentialType type,
    required String identifier,
    Map<String, Object?>? publicData,
    List<AssertedContact> contacts = const [],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<String?> findCredentialId({
    required CredentialType type,
    required String identifier,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> addVerifiedContacts({
    required String accountId,
    required CredentialType source,
    List<AssertedContact> contacts = const [],
  }) {
    throw UnimplementedError();
  }

  @override
  Future<void> update({
    required String id,
    String? displayName,
    String? description,
    String? imageId,
    bool dropImage = false,
    bool setHandle = false,
    String? handle,
  }) async {
    final user = await getById(id);
    storageByPublicKey[user.publicKey] = user.copyWith(
      displayName: displayName ?? user.displayName,
      description: description ?? user.description,
      handle: setHandle
          ? ((handle == null || handle.trim().isEmpty) ? '' : handle.trim())
          : user.handle,
    );
  }

  @override
  Future<void> deleteById({required String id}) async {
    storageByPublicKey.removeWhere((_, e) => e.id == id);
  }

  @override
  Future<bool> bindMutual({
    required String invitationId,
    required String userId,
  }) {
    throw UnimplementedError();
  }
}
