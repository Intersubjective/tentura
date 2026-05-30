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

  Future<UserEntity> getById(String id);

  Future<UserEntity> getByPublicKey(String publicKey);

  /// Resolve the account that owns the credential identified by
  /// `(type, identifier)` (the multi-credential auth lookup path).
  Future<UserEntity> getByCredential({
    required String type,
    required String identifier,
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
