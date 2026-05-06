import 'package:tentura_server/domain/entity/user_entity.dart';

/// Persistence port for users (implemented by the server user repository).
abstract class UserRepositoryPort {
  Future<UserEntity> create({
    required String publicKey,
    required String title,
    String? handle,
  });

  Future<UserEntity> createInvited({
    required String invitationId,
    required String publicKey,
    required String title,
    String? handle,
  });

  Future<UserEntity> getById(String id);

  Future<UserEntity> getByPublicKey(String publicKey);

  Future<void> update({
    required String id,
    String? title,
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
