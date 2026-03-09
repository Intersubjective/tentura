import 'package:injectable/injectable.dart';

import 'package:tentura_server/domain/exception.dart';

import '../user_repository.dart';
import 'data/users.dart';

@Injectable(
  as: UserRepository,
  env: [Environment.test],
  order: 1,
)
class UserRepositoryMock implements UserRepository {
  static final storageByPublicKey = <String, UserEntity>{...kUserByPublicKey};

  const UserRepositoryMock();

  @override
  Future<UserEntity> create({
    required String publicKey,
    required String title,
  }) async => storageByPublicKey.containsKey(publicKey)
      ? throw Exception('Key already exists [$publicKey]')
      : storageByPublicKey[publicKey] = UserEntity(
          id: UserEntity.newId,
          publicKey: publicKey,
          title: title,
        );

  @override
  Future<UserEntity> createInvited({
    required String invitationId,
    required String publicKey,
    required String title,
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
  Future<void> update({
    required String id,
    String? title,
    String? description,
    String? imageId,
    bool dropImage = false,
  }) async {
    final user = await getById(id);
    storageByPublicKey[user.publicKey] = user.copyWith(
      title: title ?? user.title,
      description: description ?? user.description,
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
